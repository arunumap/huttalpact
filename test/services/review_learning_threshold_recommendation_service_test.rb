require "test_helper"

class ReviewLearningThresholdRecommendationServiceTest < ActiveSupport::TestCase
  setup do
    @organization = organizations(:one)
    @user = users(:one)
    @contract = contracts(:hvac_maintenance)
    @contract.contract_reviews.destroy_all
    @as_of_date = Date.new(2026, 3, 15)
  end

  test "persists lowered recommendations when sufficient samples support it" do
    70.times do |index|
      create_learning_event(
        field_name: "title",
        decision: index.even? ? "confirmed" : "auto_accepted",
        confidence: index < 35 ? 74 : 88,
        reviewed_at: Time.zone.parse("2026-03-10 09:00:00") + index.minutes
      )
    end

    run_service

    field_recommendation = find_recommendation("title", ReviewLearningThresholdRecommendationService::ALL_CONTRACT_TYPES)
    contract_type_recommendation = find_recommendation("title", @contract.contract_type)

    assert_equal 70, field_recommendation.metric("recommended_threshold")
    assert_equal "recommended", field_recommendation.metric("reason_code")
    assert_equal 70, field_recommendation.sample_size

    assert_equal 70, contract_type_recommendation.metric("recommended_threshold")
    assert_equal "field_contract_type", contract_type_recommendation.dimension("scope")
  end

  test "keeps default threshold when minimum sample guard is not met" do
    10.times do |index|
      create_learning_event(
        field_name: "vendor_name",
        decision: "confirmed",
        confidence: 92,
        reviewed_at: Time.zone.parse("2026-03-11 10:00:00") + index.minutes
      )
    end

    run_service

    recommendation = find_recommendation("vendor_name", ReviewLearningThresholdRecommendationService::ALL_CONTRACT_TYPES)

    assert_equal 80, recommendation.metric("recommended_threshold")
    assert_equal "insufficient_total_samples", recommendation.metric("reason_code")
  end

  test "raises threshold when lower thresholds have unacceptable correction bounds" do
    40.times do |index|
      create_learning_event(
        field_name: "start_date",
        decision: index < 12 ? "edited" : "confirmed",
        confidence: 82,
        reviewed_at: Time.zone.parse("2026-03-12 08:00:00") + index.minutes
      )
    end
    40.times do |index|
      create_learning_event(
        field_name: "start_date",
        decision: "confirmed",
        confidence: 92,
        reviewed_at: Time.zone.parse("2026-03-12 12:00:00") + index.minutes
      )
    end

    run_service

    recommendation = find_recommendation("start_date", ReviewLearningThresholdRecommendationService::ALL_CONTRACT_TYPES)
    diagnostics = recommendation.metric("candidate_diagnostics")
    threshold_80 = diagnostics.find { |candidate| candidate["threshold"] == 80 }
    threshold_85 = diagnostics.find { |candidate| candidate["threshold"] == 85 }

    assert_equal 85, recommendation.metric("recommended_threshold")
    assert_equal false, threshold_80.fetch("meets_target")
    assert_equal true, threshold_85.fetch("meets_target")
  end

  test "replaces stale recommendation rows for the same period window" do
    stale = ReviewLearningAggregate.create!(
      organization: @organization,
      aggregate_type: ReviewLearningThresholdRecommendationService::AGGREGATE_TYPE,
      period_start_date: recommendation_period_start,
      period_end_date: @as_of_date,
      dimension_key: "contract_type=__all__|field_name=legacy|scope=field",
      sample_size: 3,
      source_version: 1,
      dimensions: {
        "field_name" => "legacy",
        "contract_type" => "__all__",
        "scope" => "field"
      },
      metrics: {
        "recommended_threshold" => 80
      }
    )

    create_learning_event(
      field_name: "title",
      decision: "confirmed",
      confidence: 88,
      reviewed_at: Time.zone.parse("2026-03-13 10:00:00")
    )

    run_service

    assert_not ReviewLearningAggregate.exists?(stale.id)
    assert find_recommendation("title", ReviewLearningThresholdRecommendationService::ALL_CONTRACT_TYPES).present?
  end

  private

  def run_service
    ReviewLearningThresholdRecommendationService.new(
      organization: @organization,
      as_of_date: @as_of_date
    ).call
  end

  def recommendation_scope
    ReviewLearningAggregate.where(
      organization: @organization,
      aggregate_type: ReviewLearningThresholdRecommendationService::AGGREGATE_TYPE,
      period_start_date: recommendation_period_start,
      period_end_date: @as_of_date
    )
  end

  def recommendation_period_start
    @as_of_date - (ReviewLearningThresholdRecommendationService::LOOKBACK_DAYS - 1).days
  end

  def find_recommendation(field_name, contract_type)
    recommendation_scope
      .where("dimensions ->> 'field_name' = ?", field_name)
      .where("dimensions ->> 'contract_type' = ?", contract_type)
      .first!
  end

  def create_learning_event(field_name:, decision:, confidence:, reviewed_at:)
    review = @contract.contract_reviews.create!(
      organization: @organization,
      status: "completed",
      review_type: "full",
      confidence_threshold: 80,
      total_fields: 1,
      reviewed_fields: 1,
      completed_at: reviewed_at,
      completed_by: @user
    )

    definition = ReviewFieldCatalog.find(field_name)
    field = review.fields.create!(
      field_name: field_name,
      field_group: definition&.field_group || "core",
      display_name: definition&.display_name || field_name.titleize,
      extracted_value: '"Extracted value"',
      confidence: confidence,
      source_excerpt: "Source excerpt",
      source_match_strategy: "exact",
      needs_review: confidence < review.confidence_threshold,
      status: decision,
      user_value: decision == "edited" ? '"Corrected value"' : nil,
      reviewed_at: reviewed_at,
      reviewed_by: @user,
      position: 0
    )

    usage_log = AiUsageLog.create!(
      organization: @organization,
      contract: @contract,
      ai_extraction_config: ai_extraction_configs(:generic_full_v1),
      ai_model: "claude-sonnet-4-20250514",
      extraction_mode: review.review_type,
      input_tokens: 120,
      output_tokens: 80,
      success: true
    )

    ReviewLearningEvent.create!(
      organization: @organization,
      contract: @contract,
      contract_review: review,
      contract_review_field: field,
      reviewed_by: @user,
      ai_usage_log: usage_log,
      review_type: review.review_type,
      contract_type: @contract.contract_type,
      field_name: field.field_name,
      field_group: field.field_group,
      decision: decision,
      confidence: confidence,
      confidence_threshold: review.confidence_threshold,
      needs_review: field.needs_review,
      corrected: %w[edited not_found not_applicable].include?(decision),
      extracted_value: field.extracted_value,
      final_value: field.final_value,
      user_value: field.user_value,
      source_excerpt: field.source_excerpt,
      source_match_strategy: field.source_match_strategy,
      source_excerpt_present: true,
      source_locator: { "start_offset" => 0, "end_offset" => 20 },
      evidence_quality: "strong",
      evidence_quality_score: 95,
      field_metadata: { "display_name" => field.display_name },
      review_metadata: { "review_status" => review.status },
      reviewed_at: reviewed_at
    )
  end
end
