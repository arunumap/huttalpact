class ReviewLearningAggregationService
  SOURCE_VERSION = 1
  FIELD_OUTCOME_AGGREGATE_TYPE = "field_outcome_daily"
  CONFIDENCE_CALIBRATION_AGGREGATE_TYPE = "confidence_calibration_daily"
  AGGREGATE_TYPES = [
    FIELD_OUTCOME_AGGREGATE_TYPE,
    CONFIDENCE_CALIBRATION_AGGREGATE_TYPE
  ].freeze
  CALIBRATION_BUCKET_SIZE = 10
  CORRECTED_DECISIONS = %w[edited not_found not_applicable].freeze

  def initialize(organization:, period_start_date:, period_end_date: nil)
    @organization = organization
    @period_start_date = period_start_date.to_date
    @period_end_date = (period_end_date || period_start_date).to_date
  end

  def call
    rows_by_type = build_rows(period_events).group_by { |row| row[:aggregate_type] }

    ActiveRecord::Base.transaction do
      AGGREGATE_TYPES.each do |aggregate_type|
        replace_rows_for_type!(aggregate_type, rows_by_type.fetch(aggregate_type, []))
      end
    end
  end

  private

  def period_events
    ReviewLearningEvent
      .where(organization_id: @organization.id, reviewed_at: period_time_range)
      .includes(ai_usage_log: :ai_extraction_config)
      .to_a
  end

  def period_time_range
    @period_start_date.beginning_of_day..@period_end_date.end_of_day
  end

  def build_rows(events)
    timestamp = Time.current

    build_field_outcome_rows(events, timestamp) +
      build_confidence_calibration_rows(events, timestamp)
  end

  def build_field_outcome_rows(events, timestamp)
    events
      .group_by { |event| base_dimensions_for(event) }
      .map do |dimensions, grouped_events|
        build_aggregate_row(
          aggregate_type: FIELD_OUTCOME_AGGREGATE_TYPE,
          dimensions: dimensions,
          metrics: outcome_metrics_for(grouped_events),
          events: grouped_events,
          timestamp: timestamp
        )
      end
  end

  def build_confidence_calibration_rows(events, timestamp)
    events
      .group_by { |event| base_dimensions_for(event).merge(confidence_bucket_dimensions_for(event)) }
      .map do |dimensions, grouped_events|
        build_aggregate_row(
          aggregate_type: CONFIDENCE_CALIBRATION_AGGREGATE_TYPE,
          dimensions: dimensions,
          metrics: calibration_metrics_for(grouped_events),
          events: grouped_events,
          timestamp: timestamp
        )
      end
  end

  def build_aggregate_row(aggregate_type:, dimensions:, metrics:, events:, timestamp:)
    normalized_dimensions = dimensions.stringify_keys

    {
      organization_id: @organization.id,
      aggregate_type: aggregate_type,
      period_start_date: @period_start_date,
      period_end_date: @period_end_date,
      dimension_key: dimension_key_for(normalized_dimensions),
      sample_size: events.size,
      source_version: SOURCE_VERSION,
      last_event_at: events.max_by(&:reviewed_at)&.reviewed_at,
      dimensions: normalized_dimensions,
      metrics: metrics.stringify_keys,
      created_at: timestamp,
      updated_at: timestamp
    }
  end

  def replace_rows_for_type!(aggregate_type, rows)
    scope = ReviewLearningAggregate.where(
      organization_id: @organization.id,
      aggregate_type: aggregate_type,
      period_start_date: @period_start_date,
      period_end_date: @period_end_date
    )

    if rows.empty?
      scope.delete_all
      return
    end

    dimension_keys = rows.map { |row| row.fetch(:dimension_key) }
    scope.where.not(dimension_key: dimension_keys).delete_all

    ReviewLearningAggregate.upsert_all(
      rows,
      unique_by: :idx_review_learning_aggregates_uniqueness
    )
  end

  def base_dimensions_for(event)
    {
      "field_name" => event.field_name,
      "contract_type" => event.contract_type,
      "review_type" => event.review_type,
      "model_name" => model_name_for(event),
      "model_version" => model_version_for(event),
      "source_type" => source_type_for(event),
      "source_match_strategy" => event.source_match_strategy.presence || "none"
    }
  end

  def confidence_bucket_dimensions_for(event)
    return unknown_confidence_bucket unless event.confidence.present?

    lower_bound = (event.confidence / CALIBRATION_BUCKET_SIZE) * CALIBRATION_BUCKET_SIZE
    upper_bound = [ lower_bound + CALIBRATION_BUCKET_SIZE - 1, 100 ].min

    {
      "confidence_bucket" => "#{lower_bound}-#{upper_bound}",
      "confidence_min" => lower_bound,
      "confidence_max" => upper_bound
    }
  end

  def unknown_confidence_bucket
    {
      "confidence_bucket" => "unknown",
      "confidence_min" => nil,
      "confidence_max" => nil
    }
  end

  def model_name_for(event)
    event.ai_usage_log&.ai_model.presence || "unknown"
  end

  def model_version_for(event)
    event.ai_usage_log&.ai_extraction_config&.version || "unknown"
  end

  def source_type_for(event)
    return "locator" if event.source_locator.present?
    return "excerpt" if event.source_excerpt_present?

    "none"
  end

  def outcome_metrics_for(events)
    total_count = events.size
    decisions = decision_counts(events)
    accepted_count = decisions["confirmed"] + decisions["auto_accepted"]
    corrected_count = events.count { |event| corrected_event?(event) }
    confidence_values = events.filter_map(&:confidence)
    threshold_values = events.filter_map(&:confidence_threshold)

    {
      "total_count" => total_count,
      "accepted_count" => accepted_count,
      "confirmed_count" => accepted_count,
      "manual_confirmed_count" => decisions["confirmed"],
      "auto_accepted_count" => decisions["auto_accepted"],
      "edited_count" => decisions["edited"],
      "not_found_count" => decisions["not_found"],
      "not_applicable_count" => decisions["not_applicable"],
      "corrected_count" => corrected_count,
      "error_count" => corrected_count,
      "agreement_rate" => rate(accepted_count, total_count),
      "confirmed_rate" => rate(accepted_count, total_count),
      "manual_confirmed_rate" => rate(decisions["confirmed"], total_count),
      "auto_accepted_rate" => rate(decisions["auto_accepted"], total_count),
      "edited_rate" => rate(decisions["edited"], total_count),
      "not_found_rate" => rate(decisions["not_found"], total_count),
      "not_applicable_rate" => rate(decisions["not_applicable"], total_count),
      "correction_rate" => rate(corrected_count, total_count),
      "error_rate" => rate(corrected_count, total_count),
      "average_confidence" => average(confidence_values),
      "average_confidence_threshold" => average(threshold_values),
      "confidence_present_rate" => rate(confidence_values.size, total_count)
    }
  end

  def calibration_metrics_for(events)
    outcome_metrics = outcome_metrics_for(events)
    expected_rate = expected_agreement_rate_for(outcome_metrics["average_confidence"])
    observed_rate = outcome_metrics["agreement_rate"]

    outcome_metrics.merge(
      "expected_agreement_rate" => expected_rate,
      "observed_agreement_rate" => observed_rate,
      "calibration_gap" => expected_rate.nil? ? nil : (observed_rate - expected_rate).round(4)
    )
  end

  def expected_agreement_rate_for(average_confidence)
    return nil if average_confidence.nil?

    (average_confidence / 100.0).round(4)
  end

  def corrected_event?(event)
    event.corrected? || CORRECTED_DECISIONS.include?(event.decision)
  end

  def decision_counts(events)
    events.each_with_object(Hash.new(0)) do |event, counts|
      counts[event.decision] += 1
    end
  end

  def average(values)
    return nil if values.empty?

    (values.sum.to_f / values.size).round(2)
  end

  def rate(numerator, denominator)
    return 0.0 if denominator.zero?

    (numerator.to_f / denominator).round(4)
  end

  def dimension_key_for(dimensions)
    dimensions
      .sort_by { |key, _| key }
      .map { |key, value| "#{key}=#{normalized_dimension_value(value)}" }
      .join("|")
  end

  def normalized_dimension_value(value)
    return "unknown" if value.nil?
    return "unknown" if value.is_a?(String) && value.blank?

    value
  end
end
