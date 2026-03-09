class ReviewLearningThresholdRecommendationService
  SOURCE_VERSION = 1
  AGGREGATE_TYPE = "confidence_threshold_recommendation_v1"
  ALL_CONTRACT_TYPES = "__all__"
  TARGET_MAX_CORRECTION_RATE = 0.10
  LOOKBACK_DAYS = 180
  DEFAULT_THRESHOLD = 80
  THRESHOLD_STEP = 5
  MAX_THRESHOLD_DELTA = 10
  MIN_CANDIDATE_SAMPLE_SIZE = 20
  MIN_LOWERING_SAMPLE_SIZE = 60
  WILSON_Z_SCORE = 1.96
  CORRECTED_DECISIONS = %w[edited not_found not_applicable].freeze
  MIN_TOTAL_SAMPLE_SIZE_BY_SCOPE = {
    "field" => 40,
    "field_contract_type" => 25
  }.freeze

  def initialize(organization:, as_of_date: Date.current, lookback_days: LOOKBACK_DAYS,
    default_threshold: DEFAULT_THRESHOLD)
    @organization = organization
    @as_of_date = as_of_date.to_date
    @lookback_days = lookback_days
    @default_threshold = default_threshold
    @period_start_date = @as_of_date - (@lookback_days - 1).days
  end

  def call
    rows = build_rows

    ActiveRecord::Base.transaction do
      replace_rows!(rows)
    end

    rows
  end

  private

  def build_rows
    timestamp = Time.current
    rows = []

    grouped_events_for_fields.each do |dimensions, events|
      rows << build_row(dimensions:, events:, timestamp:)
    end

    grouped_events_for_field_contract_types.each do |dimensions, events|
      rows << build_row(dimensions:, events:, timestamp:)
    end

    rows
  end

  def grouped_events_for_fields
    lookback_events.group_by do |event|
      {
        "field_name" => event.field_name,
        "contract_type" => ALL_CONTRACT_TYPES,
        "scope" => "field"
      }
    end
  end

  def grouped_events_for_field_contract_types
    lookback_events.group_by do |event|
      {
        "field_name" => event.field_name,
        "contract_type" => normalized_contract_type(event.contract_type),
        "scope" => "field_contract_type"
      }
    end
  end

  def build_row(dimensions:, events:, timestamp:)
    recommendation = recommendation_for(events:, scope: dimensions.fetch("scope"))
    normalized_dimensions = dimensions.stringify_keys
    metrics = recommendation.fetch(:metrics)

    {
      organization_id: @organization.id,
      aggregate_type: AGGREGATE_TYPE,
      period_start_date: @period_start_date,
      period_end_date: @as_of_date,
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

  def recommendation_for(events:, scope:)
    min_total_sample_size = MIN_TOTAL_SAMPLE_SIZE_BY_SCOPE.fetch(scope)
    corrected_count = events.count { |event| corrected_event?(event) }
    overall_correction_rate = rate(corrected_count, events.size)
    candidate_results = evaluate_candidates(events)
    eligible_candidates = candidate_results.select { |candidate| candidate["meets_target"] }

    recommendation =
      if events.size < min_total_sample_size
        default_recommendation(
          reason_code: "insufficient_total_samples",
          explanation: "Kept default threshold #{@default_threshold} because #{events.size} " \
            "samples is below the minimum #{min_total_sample_size} for #{scope}."
        )
      elsif eligible_candidates.empty?
        default_recommendation(
          reason_code: "no_safe_candidate",
          explanation: "Kept default threshold #{@default_threshold} because no candidate " \
            "threshold met the correction-rate target of #{TARGET_MAX_CORRECTION_RATE}."
        )
      else
        chosen = eligible_candidates.min_by { |candidate| candidate.fetch("threshold") }

        if lowering_guard_triggered?(chosen)
          default_recommendation(
            reason_code: "insufficient_lowering_evidence",
            explanation: "Kept default threshold #{@default_threshold}; lowering to #{chosen["threshold"]} " \
              "requires at least #{MIN_LOWERING_SAMPLE_SIZE} samples but only #{chosen["sample_size"]} were available."
          )
        else
          {
            "recommended_threshold" => chosen["threshold"],
            "reason_code" => "recommended",
            "explanation" => "Recommended #{chosen["threshold"]} because corrected upper bound " \
              "#{chosen["correction_upper_bound"]} is within target #{TARGET_MAX_CORRECTION_RATE} " \
              "for #{chosen["sample_size"]} samples."
          }
        end
      end

    {
      metrics: recommendation.merge(
        "default_threshold" => @default_threshold,
        "overall_sample_size" => events.size,
        "overall_corrected_count" => corrected_count,
        "overall_correction_rate" => overall_correction_rate,
        "target_max_correction_rate" => TARGET_MAX_CORRECTION_RATE,
        "min_total_sample_size" => min_total_sample_size,
        "min_candidate_sample_size" => MIN_CANDIDATE_SAMPLE_SIZE,
        "candidate_diagnostics" => candidate_results
      )
    }
  end

  def evaluate_candidates(events)
    candidate_thresholds.map do |threshold|
      candidate_events = events.select { |event| event.confidence >= threshold }
      corrected_count = candidate_events.count { |event| corrected_event?(event) }
      sample_size = candidate_events.size
      correction_rate = rate(corrected_count, sample_size)
      correction_upper_bound = sample_size.zero? ? nil : wilson_upper_bound(corrected_count, sample_size)
      eligible = sample_size >= MIN_CANDIDATE_SAMPLE_SIZE
      meets_target = eligible && correction_upper_bound <= TARGET_MAX_CORRECTION_RATE

      {
        "threshold" => threshold,
        "sample_size" => sample_size,
        "corrected_count" => corrected_count,
        "correction_rate" => correction_rate,
        "correction_upper_bound" => correction_upper_bound,
        "meets_target" => meets_target
      }
    end
  end

  def default_recommendation(reason_code:, explanation:)
    {
      "recommended_threshold" => @default_threshold,
      "reason_code" => reason_code,
      "explanation" => explanation
    }
  end

  def lowering_guard_triggered?(chosen_candidate)
    chosen_candidate["threshold"] < @default_threshold &&
      chosen_candidate["sample_size"] < MIN_LOWERING_SAMPLE_SIZE
  end

  def lookback_events
    @lookback_events ||= ReviewLearningEvent
      .where(organization_id: @organization.id, reviewed_at: lookback_range)
      .where.not(confidence: nil)
      .to_a
  end

  def lookback_range
    @period_start_date.beginning_of_day..@as_of_date.end_of_day
  end

  def replace_rows!(rows)
    scope = ReviewLearningAggregate.where(
      organization_id: @organization.id,
      aggregate_type: AGGREGATE_TYPE,
      period_start_date: @period_start_date,
      period_end_date: @as_of_date
    )

    if rows.empty?
      scope.delete_all
      return
    end

    dimension_keys = rows.map { |row| row.fetch(:dimension_key) }
    scope.where.not(dimension_key: dimension_keys).delete_all

    ReviewLearningAggregate.upsert_all(rows, unique_by: :idx_review_learning_aggregates_uniqueness)
  end

  def candidate_thresholds
    lower_bound = [ @default_threshold - MAX_THRESHOLD_DELTA, 0 ].max
    upper_bound = [ @default_threshold + MAX_THRESHOLD_DELTA, 100 ].min

    ((lower_bound..upper_bound).step(THRESHOLD_STEP).to_a + [ @default_threshold ]).uniq.sort
  end

  def corrected_event?(event)
    event.corrected? || CORRECTED_DECISIONS.include?(event.decision)
  end

  def normalized_contract_type(contract_type)
    contract_type.presence || "unknown"
  end

  def rate(numerator, denominator)
    return 0.0 if denominator.zero?

    (numerator.to_f / denominator).round(4)
  end

  def wilson_upper_bound(corrected_count, sample_size)
    return 1.0 if sample_size.zero?

    p_hat = corrected_count.to_f / sample_size
    z_squared = WILSON_Z_SCORE**2
    denominator = 1 + (z_squared / sample_size)
    center = p_hat + (z_squared / (2 * sample_size))
    margin = WILSON_Z_SCORE * Math.sqrt((p_hat * (1 - p_hat) + (z_squared / (4 * sample_size))) / sample_size)

    ((center + margin) / denominator).round(4)
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
