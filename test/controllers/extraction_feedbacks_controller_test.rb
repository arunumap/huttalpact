require "test_helper"

class ExtractionFeedbacksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @contract = contracts(:hvac_maintenance)
    sign_in_as(@user)
  end

  test "requires authentication" do
    sign_out
    post contract_extraction_feedbacks_path(@contract), params: {
      extraction_feedback: { rating: "positive" }
    }
    assert_redirected_to new_session_path
  end

  test "creates positive feedback" do
    ExtractionFeedback.where(contract: @contract, user: @user).delete_all

    assert_difference "ExtractionFeedback.count", 1 do
      post contract_extraction_feedbacks_path(@contract), params: {
        extraction_feedback: { rating: "positive", comment: "Looks great!" }
      }
    end

    feedback = ExtractionFeedback.last
    assert_equal "positive", feedback.rating
    assert_equal "Looks great!", feedback.comment
    assert_equal @contract, feedback.contract
    assert_equal @user, feedback.user
  end

  test "upserts feedback on repeat submission" do
    existing = extraction_feedbacks(:one)
    assert_equal "positive", existing.rating

    assert_no_difference "ExtractionFeedback.count" do
      post contract_extraction_feedbacks_path(@contract), params: {
        extraction_feedback: { rating: "negative", comment: "Not accurate" }
      }
    end

    existing.reload
    assert_equal "negative", existing.rating
    assert_equal "Not accurate", existing.comment
  end

  test "responds with turbo stream" do
    ExtractionFeedback.where(contract: @contract, user: @user).delete_all

    post contract_extraction_feedbacks_path(@contract),
         params: { extraction_feedback: { rating: "positive" } },
         as: :turbo_stream
    assert_response :success
  end
end
