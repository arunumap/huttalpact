require "test_helper"

class RefreshReviewLearningAggregatesJobTest < ActiveSupport::TestCase
  setup do
    @organization = organizations(:one)
  end

  test "invokes aggregation service with parsed period dates" do
    captured_aggregation_kwargs = nil
    aggregation_service = Minitest::Mock.new
    aggregation_service.expect(:call, nil)
    captured_recommendation_kwargs = nil
    recommendation_service = Minitest::Mock.new
    recommendation_service.expect(:call, nil)

    ReviewLearningAggregationService.stub(:new, ->(**kwargs) {
      captured_aggregation_kwargs = kwargs
      aggregation_service
    }) do
      ReviewLearningThresholdRecommendationService.stub(:new, ->(**kwargs) {
        captured_recommendation_kwargs = kwargs
        recommendation_service
      }) do
        RefreshReviewLearningAggregatesJob.perform_now(
          @organization.id,
          "2026-03-10",
          "2026-03-11"
        )
      end
    end

    aggregation_service.verify
    recommendation_service.verify
    assert_equal @organization, captured_aggregation_kwargs[:organization]
    assert_equal Date.new(2026, 3, 10), captured_aggregation_kwargs[:period_start_date]
    assert_equal Date.new(2026, 3, 11), captured_aggregation_kwargs[:period_end_date]
    assert_equal @organization, captured_recommendation_kwargs[:organization]
    assert_equal Date.new(2026, 3, 11), captured_recommendation_kwargs[:as_of_date]
  end

  test "handles missing organization gracefully" do
    assert_nothing_raised do
      RefreshReviewLearningAggregatesJob.perform_now("00000000-0000-0000-0000-000000000000", "2026-03-10")
    end
  end
end
