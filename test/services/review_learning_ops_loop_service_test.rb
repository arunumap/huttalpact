require "test_helper"

class ReviewLearningOpsLoopServiceTest < ActiveSupport::TestCase
  setup do
    @organization = organizations(:one)
    @other_organization = organizations(:two)
    @user = users(:one)
    @other_user = users(:two)
    @contract = contracts(:hvac_maintenance)
    @other_contract = contracts(:other_org_contract)

    @contract.contract_reviews.destroy_all
    @other_contract.contract_reviews.destroy_all
  end

  test "refreshes aggregate dates in lookback window and threshold recommendations" do
    create_learning_event(
      contract: @contract,
      organization: @organization,
      user: @user,
      reviewed_at: Time.zone.parse("2026-03-14 10:00:00")
    )
    create_learning_event(
      contract: @contract,
      organization: @organization,
      user: @user,
      reviewed_at: Time.zone.parse("2026-03-15 11:00:00")
    )
    create_learning_event(
      contract: @contract,
      organization: @organization,
      user: @user,
      reviewed_at: Time.zone.parse("2026-03-01 09:00:00")
    )

    captured_aggregation_dates = []
    captured_recommendation_kwargs = nil
    aggregation_service = Object.new
    aggregation_service.define_singleton_method(:call) { nil }
    recommendation_service = Object.new
    recommendation_service.define_singleton_method(:call) { [ { "ok" => true } ] }

    summaries = nil

    ReviewLearningAggregationService.stub(:new, lambda { |**kwargs|
      captured_aggregation_dates << kwargs[:period_start_date]
      aggregation_service
    }) do
      ReviewLearningThresholdRecommendationService.stub(:new, lambda { |**kwargs|
        captured_recommendation_kwargs = kwargs
        recommendation_service
      }) do
        summaries = ReviewLearningOpsLoopService.new(
          as_of_date: Date.new(2026, 3, 15),
          aggregate_lookback_days: 2,
          organization: @organization
        ).call
      end
    end

    assert_equal [ Date.new(2026, 3, 14), Date.new(2026, 3, 15) ], captured_aggregation_dates.sort
    assert_equal @organization, captured_recommendation_kwargs[:organization]
    assert_equal Date.new(2026, 3, 15), captured_recommendation_kwargs[:as_of_date]
    assert_equal 1, summaries.size
    assert_equal 2, summaries.first[:refreshed_dates_count]
    assert_equal 1, summaries.first[:recommendation_count]
  end

  test "iterates organizations that have review learning events when no organization is provided" do
    create_learning_event(
      contract: @contract,
      organization: @organization,
      user: @user,
      reviewed_at: Time.zone.parse("2026-03-15 09:00:00")
    )
    create_learning_event(
      contract: @other_contract,
      organization: @other_organization,
      user: @other_user,
      reviewed_at: Time.zone.parse("2026-03-15 09:05:00")
    )

    refreshed_organization_ids = []
    aggregation_service = Object.new
    aggregation_service.define_singleton_method(:call) { nil }
    recommendation_service = Object.new
    recommendation_service.define_singleton_method(:call) { [] }

    ReviewLearningAggregationService.stub(:new, lambda { |**_kwargs| aggregation_service }) do
      ReviewLearningThresholdRecommendationService.stub(:new, lambda { |**kwargs|
        refreshed_organization_ids << kwargs[:organization].id
        recommendation_service
      }) do
        ReviewLearningOpsLoopService.new(
          as_of_date: Date.new(2026, 3, 15),
          aggregate_lookback_days: 7
        ).call
      end
    end

    assert_equal [ @organization.id, @other_organization.id ].sort, refreshed_organization_ids.sort
  end

  private

  def create_learning_event(contract:, organization:, user:, reviewed_at:)
    review = contract.contract_reviews.create!(
      organization: organization,
      status: "completed",
      review_type: "full",
      confidence_threshold: 80,
      total_fields: 1,
      reviewed_fields: 1,
      completed_at: reviewed_at,
      completed_by: user
    )

    definition = ReviewFieldCatalog.find("title")
    field = review.fields.create!(
      field_name: "title",
      field_group: definition&.field_group || "core",
      display_name: definition&.display_name || "Title",
      extracted_value: '"Contract Title"',
      confidence: 90,
      source_excerpt: "Contract Title",
      source_match_strategy: "exact",
      needs_review: false,
      status: "confirmed",
      reviewed_at: reviewed_at,
      reviewed_by: user,
      position: 0
    )

    ReviewLearningEvent.create!(
      organization: organization,
      contract: contract,
      contract_review: review,
      contract_review_field: field,
      reviewed_by: user,
      review_type: review.review_type,
      contract_type: contract.contract_type,
      field_name: field.field_name,
      field_group: field.field_group,
      decision: field.status,
      confidence: field.confidence,
      confidence_threshold: review.confidence_threshold,
      needs_review: field.needs_review,
      corrected: false,
      extracted_value: field.extracted_value,
      final_value: field.final_value,
      user_value: field.user_value,
      source_excerpt: field.source_excerpt,
      source_match_strategy: field.source_match_strategy,
      source_excerpt_present: true,
      source_locator: { "start_offset" => 0, "end_offset" => 14 },
      evidence_quality: "strong",
      evidence_quality_score: 95,
      field_metadata: { "display_name" => field.display_name },
      review_metadata: { "review_status" => review.status },
      reviewed_at: reviewed_at
    )
  end
end
