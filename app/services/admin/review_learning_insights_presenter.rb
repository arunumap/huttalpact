class Admin::ReviewLearningInsightsPresenter
  DEFAULT_LOOKBACK_DAYS = 30
  WORST_FIELDS_LIMIT = 5
  UNKNOWN_DIMENSION = "unknown"
  OUTCOME_AGGREGATE_TYPE = ReviewLearningAggregationService::FIELD_OUTCOME_AGGREGATE_TYPE
  CALIBRATION_AGGREGATE_TYPE = ReviewLearningAggregationService::CONFIDENCE_CALIBRATION_AGGREGATE_TYPE

  attr_reader :start_date, :end_date, :contract_type, :field_name

  def initialize(params:, scope: ReviewLearningAggregate.all)
    @scope = scope
    @start_date = parse_date(params[:start_date]) || DEFAULT_LOOKBACK_DAYS.days.ago.to_date
    @end_date = parse_date(params[:end_date]) || Date.current
    normalize_date_range!
    @contract_type = params[:contract_type].presence
    @field_name = params[:field_name].presence
  end

  def overview
    total_volume = outcome_aggregates.sum(&:sample_size)
    corrected_count = outcome_aggregates.sum { |aggregate| metric_value(aggregate, "corrected_count") }
    error_count = outcome_aggregates.sum { |aggregate| metric_value(aggregate, "error_count") }

    {
      total_volume:,
      corrected_count: corrected_count.to_i,
      error_count: error_count.to_i,
      correction_rate: rate(corrected_count, total_volume),
      error_rate: rate(error_count, total_volume)
    }
  end

  def calibration_summary
    observed_agreement_rate = weighted_metric(calibration_aggregates, "observed_agreement_rate")
    expected_agreement_rate = weighted_metric(calibration_aggregates, "expected_agreement_rate")

    {
      total_volume: calibration_aggregates.sum(&:sample_size),
      observed_agreement_rate:,
      expected_agreement_rate:,
      calibration_gap: calibration_gap(observed_agreement_rate, expected_agreement_rate)
    }
  end

  def worst_fields(limit: WORST_FIELDS_LIMIT)
    outcome_aggregates
      .group_by { |aggregate| normalize_dimension(aggregate.dimension("field_name")) }
      .map { |name, aggregates| summarize_field(name, aggregates) }
      .sort_by { |summary| [ -(summary[:error_rate] || 0.0), -summary[:total_volume], summary[:field_name] ] }
      .first(limit)
  end

  def calibration_buckets
    calibration_aggregates
      .group_by { |aggregate| normalize_dimension(aggregate.dimension("confidence_bucket")) }
      .map { |bucket, aggregates| summarize_bucket(bucket, aggregates) }
      .sort_by { |summary| bucket_sort_key(summary[:bucket]) }
  end

  def contract_type_options
    base_outcome_scope
      .distinct
      .pluck(Arel.sql("dimensions ->> 'contract_type'"))
      .compact_blank
      .sort
  end

  def field_options
    scope = base_outcome_scope
    scope = scope.where("dimensions ->> 'contract_type' = ?", contract_type) if contract_type.present?

    scope
      .distinct
      .pluck(Arel.sql("dimensions ->> 'field_name'"))
      .compact_blank
      .sort
  end

  private

  def parse_date(value)
    return if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def normalize_date_range!
    return unless start_date > end_date

    @start_date, @end_date = end_date, start_date
  end

  def base_scope
    @base_scope ||= @scope.for_period(start_date, end_date)
  end

  def base_outcome_scope
    @base_outcome_scope ||= base_scope.for_type(OUTCOME_AGGREGATE_TYPE)
  end

  def outcome_scope
    @outcome_scope ||= apply_dimension_filters(base_outcome_scope)
  end

  def calibration_scope
    @calibration_scope ||= apply_dimension_filters(base_scope.for_type(CALIBRATION_AGGREGATE_TYPE))
  end

  def apply_dimension_filters(scope)
    filtered_scope = scope
    filtered_scope = filtered_scope.where("dimensions ->> 'contract_type' = ?", contract_type) if contract_type.present?
    filtered_scope = filtered_scope.for_field(field_name) if field_name.present?
    filtered_scope
  end

  def outcome_aggregates
    @outcome_aggregates ||= outcome_scope.to_a
  end

  def calibration_aggregates
    @calibration_aggregates ||= calibration_scope.to_a
  end

  def metric_value(aggregate, metric_name)
    aggregate.metric(metric_name).to_f
  end

  def weighted_metric(aggregates, metric_name)
    weighted_total = 0.0
    total_volume = 0

    aggregates.each do |aggregate|
      metric = aggregate.metric(metric_name)
      next if metric.nil?

      weighted_total += metric.to_f * aggregate.sample_size
      total_volume += aggregate.sample_size
    end

    return nil if total_volume.zero?

    (weighted_total / total_volume).round(4)
  end

  def summarize_field(name, aggregates)
    total_volume = aggregates.sum(&:sample_size)
    corrected_count = aggregates.sum { |aggregate| metric_value(aggregate, "corrected_count") }
    error_count = aggregates.sum { |aggregate| metric_value(aggregate, "error_count") }

    {
      field_name: name,
      total_volume:,
      corrected_count: corrected_count.to_i,
      error_count: error_count.to_i,
      correction_rate: rate(corrected_count, total_volume),
      error_rate: rate(error_count, total_volume)
    }
  end

  def summarize_bucket(bucket, aggregates)
    observed_agreement_rate = weighted_metric(aggregates, "observed_agreement_rate")
    expected_agreement_rate = weighted_metric(aggregates, "expected_agreement_rate")

    {
      bucket:,
      total_volume: aggregates.sum(&:sample_size),
      observed_agreement_rate:,
      expected_agreement_rate:,
      calibration_gap: calibration_gap(observed_agreement_rate, expected_agreement_rate)
    }
  end

  def rate(numerator, denominator)
    return nil if denominator.zero?

    (numerator.to_f / denominator).round(4)
  end

  def calibration_gap(observed_agreement_rate, expected_agreement_rate)
    return nil if observed_agreement_rate.nil? || expected_agreement_rate.nil?

    (observed_agreement_rate - expected_agreement_rate).round(4)
  end

  def normalize_dimension(value)
    value.to_s.presence || UNKNOWN_DIMENSION
  end

  def bucket_sort_key(bucket)
    return [ 1, Float::INFINITY ] if bucket == UNKNOWN_DIMENSION

    [ 0, bucket.split("-").first.to_i ]
  end
end
