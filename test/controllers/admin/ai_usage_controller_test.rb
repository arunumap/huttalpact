require "test_helper"

class Admin::AiUsageControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin_user = admin_users(:one)
  end

  test "requires admin authentication" do
    get admin_ai_usage_index_path
    assert_redirected_to new_admin_session_path
  end

  test "index shows usage stats and feedback analytics" do
    sign_in_as_admin(@admin_user)
    get admin_ai_usage_index_path
    assert_response :success
    assert_select "p", text: "User Feedback"
    assert_select "h3", text: "Extraction Stats by Mode"
  end

  test "index filters by date range" do
    sign_in_as_admin(@admin_user)
    get admin_ai_usage_index_path, params: {
      start_date: 7.days.ago.to_date,
      end_date: Date.current
    }
    assert_response :success
  end
end
