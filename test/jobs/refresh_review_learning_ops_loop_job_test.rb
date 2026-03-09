require "test_helper"

class RefreshReviewLearningOpsLoopJobTest < ActiveSupport::TestCase
  setup do
    @organization = organizations(:one)
  end

  test "delegates parsed arguments to ops loop service" do
    captured_kwargs = nil
    service = Minitest::Mock.new
    service.expect(:call, [])

    ReviewLearningOpsLoopService.stub(:new, lambda { |**kwargs|
      captured_kwargs = kwargs
      service
    }) do
      RefreshReviewLearningOpsLoopJob.perform_now("2026-03-15", 14, @organization.id)
    end

    service.verify
    assert_equal Date.new(2026, 3, 15), captured_kwargs[:as_of_date]
    assert_equal 14, captured_kwargs[:aggregate_lookback_days]
    assert_equal @organization, captured_kwargs[:organization]
  end

  test "skips service execution when organization is missing" do
    invoked = false

    ReviewLearningOpsLoopService.stub(:new, lambda { |**_kwargs|
      invoked = true
      Minitest::Mock.new
    }) do
      assert_nothing_raised do
        RefreshReviewLearningOpsLoopJob.perform_now(
          "2026-03-15",
          14,
          "00000000-0000-0000-0000-000000000000"
        )
      end
    end

    refute invoked
  end
end
