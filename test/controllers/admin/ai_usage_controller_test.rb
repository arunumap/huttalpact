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

  test "index shows average cost and per-log approximate cost" do
    sign_in_as_admin(@admin_user)

    config = ai_extraction_configs(:generic_full_v1)
    AiUsageLog.create!(
      organization: organizations(:one),
      contract: contracts(:hvac_maintenance),
      ai_model: config.ai_model,
      input_tokens: 200_000,
      output_tokens: 100_000,
      extraction_mode: "full",
      success: true,
      ai_extraction_config: config
    )

    get admin_ai_usage_index_path

    assert_response :success
    assert_select "p", text: "Avg Cost / Extraction"
    assert_select "th", text: "Approx Cost"
    assert_select "p", text: "in 200,000 / out 100,000"
    assert_select "td", text: "$2.1"
  end
end
