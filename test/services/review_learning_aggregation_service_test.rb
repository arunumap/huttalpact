require "test_helper"

class ReviewLearningAggregationServiceTest < ActiveSupport::TestCase
  setup do
    @organization = organizations(:one)
    @user = users(:one)
    @contract = contracts(:hvac_maintenance)
    @contract.contract_reviews.destroy_all

    @period_date = Date.new(2026, 3, 10)
  end

  test "calculates field outcome and confidence calibration metrics" do
    events = seed_events_for_metrics

    aggregate_for_period

    outcome_scope = aggregate_scope(ReviewLearningAggregationService::FIELD_OUTCOME_AGGREGATE_TYPE)
    calibration_scope = aggregate_scope(ReviewLearningAggregationService::CONFIDENCE_CALIBRATION_AGGREGATE_TYPE)

    assert_equal 2, outcome_scope.count
    assert_equal 4, calibration_scope.count

    locator_outcome = find_aggregate(outcome_scope, "model_version" => 1, "source_type" => "locator")
    assert_equal 4, locator_outcome.sample_size
    assert_equal 4, locator_outcome.metric("total_count")
    assert_equal 2, locator_outcome.metric("confirmed_count")
    assert_equal 1, locator_outcome.metric("edited_count")
    assert_equal 1, locator_outcome.metric("not_found_count")
    assert_equal 0, locator_outcome.metric("not_applicable_count")
    assert_in_delta 0.5, locator_outcome.metric("confirmed_rate"), 0.0001
    assert_in_delta 0.5, locator_outcome.metric("correction_rate"), 0.0001
    assert_in_delta 0.5, locator_outcome.metric("error_rate"), 0.0001

    excerpt_outcome = find_aggregate(outcome_scope, "model_version" => 2, "source_type" => "excerpt")
    assert_equal 1, excerpt_outcome.sample_size
    assert_equal 1, excerpt_outcome.metric("not_applicable_count")
    assert_in_delta 1.0, excerpt_outcome.metric("not_applicable_rate"), 0.0001

    high_confidence_bucket = find_aggregate(
      calibration_scope,
      "model_version" => 1,
      "source_type" => "locator",
      "confidence_bucket" => "90-99"
    )
    assert_equal 2, high_confidence_bucket.sample_size
    assert_in_delta 1.0, high_confidence_bucket.metric("agreement_rate"), 0.0001
    assert_in_delta 0.935, high_confidence_bucket.metric("expected_agreement_rate"), 0.0001
    assert_in_delta 0.065, high_confidence_bucket.metric("calibration_gap"), 0.0001

    mid_confidence_bucket = find_aggregate(
      calibration_scope,
      "model_version" => 1,
      "source_type" => "locator",
      "confidence_bucket" => "60-69"
    )
    assert_equal 1, mid_confidence_bucket.sample_size
    assert_in_delta 0.0, mid_confidence_bucket.metric("agreement_rate"), 0.0001

    assert_equal "not_found", events[:not_found].decision
  end

  test "reruns are idempotent and replace stale confidence slices" do
    events = seed_events_for_metrics

    aggregate_for_period

    outcome_scope = aggregate_scope(ReviewLearningAggregationService::FIELD_OUTCOME_AGGREGATE_TYPE)
    calibration_scope = aggregate_scope(ReviewLearningAggregationService::CONFIDENCE_CALIBRATION_AGGREGATE_TYPE)
    initial_calibration_count = calibration_scope.count
    locator_outcome = find_aggregate(outcome_scope, "model_version" => 1, "source_type" => "locator")
    locator_outcome_id = locator_outcome.id

    aggregate_for_period

    assert_equal 2, outcome_scope.reload.count
    assert_equal initial_calibration_count, calibration_scope.reload.count
    assert_equal locator_outcome_id, find_aggregate(outcome_scope, "model_version" => 1, "source_type" => "locator").id

    events[:not_found].update!(confidence: 85)
    aggregate_for_period

    calibration_scope = aggregate_scope(ReviewLearningAggregationService::CONFIDENCE_CALIBRATION_AGGREGATE_TYPE)
    stale_bucket = find_aggregate(
      calibration_scope,
      "model_version" => 1,
      "source_type" => "locator",
      "confidence_bucket" => "70-79"
    )
    assert_nil stale_bucket

    new_bucket = find_aggregate(
      calibration_scope,
      "model_version" => 1,
      "source_type" => "locator",
      "confidence_bucket" => "80-89"
    )
    assert_equal 1, new_bucket.sample_size
    assert_equal 1, new_bucket.metric("not_found_count")
    assert_equal initial_calibration_count, calibration_scope.count
  end

  private

  def aggregate_for_period
    ReviewLearningAggregationService.new(
      organization: @organization,
      period_start_date: @period_date
    ).call
  end

  def aggregate_scope(aggregate_type)
    ReviewLearningAggregate.where(
      organization: @organization,
      aggregate_type: aggregate_type,
      period_start_date: @period_date,
      period_end_date: @period_date
    )
  end

  def find_aggregate(scope, expected_dimensions)
    scope.detect do |aggregate|
      expected_dimensions.all? do |key, value|
        aggregate.dimension(key) == value
      end
    end
  end

  def seed_events_for_metrics
    config_v1 = ai_extraction_configs(:generic_full_v1)
    config_v2 = ai_extraction_configs(:generic_full_v2_inactive)

    create_learning_event(
      decision: "confirmed",
      confidence: 92,
      reviewed_at: Time.zone.parse("2026-03-10 10:00:00"),
      source_type: :locator,
      source_match_strategy: "exact",
      ai_model: "claude-sonnet-4-20250514",
      ai_extraction_config: config_v1
    )
    create_learning_event(
      decision: "auto_accepted",
      confidence: 95,
      reviewed_at: Time.zone.parse("2026-03-10 10:05:00"),
      source_type: :locator,
      source_match_strategy: "exact",
      ai_model: "claude-sonnet-4-20250514",
      ai_extraction_config: config_v1
    )
    create_learning_event(
      decision: "edited",
      confidence: 65,
      reviewed_at: Time.zone.parse("2026-03-10 10:10:00"),
      source_type: :locator,
      source_match_strategy: "exact",
      ai_model: "claude-sonnet-4-20250514",
      ai_extraction_config: config_v1
    )
    not_found = create_learning_event(
      decision: "not_found",
      confidence: 72,
      reviewed_at: Time.zone.parse("2026-03-10 10:15:00"),
      source_type: :locator,
      source_match_strategy: "exact",
      ai_model: "claude-sonnet-4-20250514",
      ai_extraction_config: config_v1
    )
    create_learning_event(
      decision: "not_applicable",
      confidence: 55,
      reviewed_at: Time.zone.parse("2026-03-10 10:20:00"),
      source_type: :excerpt,
      source_match_strategy: "fuzzy",
      ai_model: "claude-opus-4-20250514",
      ai_extraction_config: config_v2
    )

    { not_found: not_found }
  end

  def create_learning_event(decision:, confidence:, reviewed_at:, source_type:, source_match_strategy:, ai_model:, ai_extraction_config:)
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

    field = review.fields.create!(
      field_name: "title",
      field_group: "core",
      display_name: "Title",
      extracted_value: '"Contract Title"',
      confidence: confidence,
      source_excerpt: source_type == :none ? nil : "Source excerpt",
      source_match_strategy: source_match_strategy,
      needs_review: confidence.nil? || confidence < review.confidence_threshold,
      status: decision,
      user_value: decision == "edited" ? '"Updated Contract Title"' : nil,
      reviewed_at: reviewed_at,
      reviewed_by: @user,
      position: 0
    )

    usage_log = AiUsageLog.create!(
      organization: @organization,
      contract: @contract,
      ai_extraction_config: ai_extraction_config,
      ai_model: ai_model,
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
      source_match_strategy: source_match_strategy,
      source_excerpt_present: source_type != :none,
      source_locator: source_type == :locator ? { "start_offset" => 0, "end_offset" => 20 } : {},
      evidence_quality: source_type == :none ? "missing" : source_type == :locator ? "strong" : "moderate",
      evidence_quality_score: source_type == :none ? nil : source_type == :locator ? 95 : 75,
      field_metadata: { "display_name" => field.display_name },
      review_metadata: { "review_status" => review.status },
      reviewed_at: reviewed_at
    )
  end
end
