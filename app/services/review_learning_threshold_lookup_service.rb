class ReviewLearningThresholdLookupService
  def initialize(organization:, field_name:, contract_type: nil,
    fallback_threshold: ReviewLearningThresholdRecommendationService::DEFAULT_THRESHOLD)
    @organization = organization
    @field_name = field_name
    @contract_type = contract_type
    @fallback_threshold = fallback_threshold
  end

  def call
    recommendation = contract_type_recommendation || field_recommendation
    return default_response unless recommendation

    metrics = recommendation.metrics
    {
      threshold: normalized_threshold(metrics["recommended_threshold"]),
      source: recommendation.dimensions["scope"],
      reason_code: metrics["reason_code"],
      sample_size: recommendation.sample_size,
      period_start_date: recommendation.period_start_date,
      period_end_date: recommendation.period_end_date
    }
  end

  private

  def contract_type_recommendation
    return unless @contract_type.present?

    latest_recommendation_for(contract_type: @contract_type)
  end

  def field_recommendation
    latest_recommendation_for(contract_type: ReviewLearningThresholdRecommendationService::ALL_CONTRACT_TYPES)
  end

  def latest_recommendation_for(contract_type:)
    ReviewLearningAggregate.where(
      organization_id: @organization.id,
      aggregate_type: ReviewLearningThresholdRecommendationService::AGGREGATE_TYPE
    )
      .where("dimensions ->> 'field_name' = ?", @field_name)
      .where("dimensions ->> 'contract_type' = ?", contract_type)
      .order(period_end_date: :desc, updated_at: :desc)
      .first
  end

  def default_response
    {
      threshold: @fallback_threshold,
      source: "default",
      reason_code: "no_recommendation",
      sample_size: 0,
      period_start_date: nil,
      period_end_date: nil
    }
  end

  def normalized_threshold(value)
    threshold = value.to_i
    threshold.zero? ? @fallback_threshold : threshold
  end
end
