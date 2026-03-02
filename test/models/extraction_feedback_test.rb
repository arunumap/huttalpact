require "test_helper"

class ExtractionFeedbackTest < ActiveSupport::TestCase
  setup do
    @feedback = extraction_feedbacks(:one)
    @organization = organizations(:one)
  end

  test "valid feedback is valid" do
    assert @feedback.valid?
  end

  test "requires rating" do
    @feedback.rating = nil
    assert_not @feedback.valid?
  end

  test "rating must be positive or negative" do
    @feedback.rating = "neutral"
    assert_not @feedback.valid?
  end

  test "one feedback per user per contract" do
    dupe = ExtractionFeedback.new(
      contract: @feedback.contract,
      user: @feedback.user,
      organization: @organization,
      rating: "negative"
    )
    assert_not dupe.valid?
    assert_includes dupe.errors[:user_id], "has already submitted feedback for this contract"
  end

  test "different user can submit feedback for same contract" do
    ActsAsTenant.with_tenant(@organization) do
      feedback = ExtractionFeedback.new(
        contract: contracts(:hvac_maintenance),
        user: users(:two),
        organization: @organization,
        rating: "negative"
      )
      # user two is in org two, but let's use a user in org one for this test
      # The uniqueness is on [contract_id, user_id], user two hasn't submitted
      assert feedback.valid?
    end
  end

  test "positive scope" do
    assert_includes ExtractionFeedback.positive, @feedback
  end

  test "negative scope" do
    assert_not_includes ExtractionFeedback.negative, @feedback
  end

  test "comment is optional" do
    @feedback.comment = nil
    assert @feedback.valid?
  end
end
