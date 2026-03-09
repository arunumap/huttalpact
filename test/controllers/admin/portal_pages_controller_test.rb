require "test_helper"

class Admin::PortalPagesControllerTest < ActionDispatch::IntegrationTest
  setup { @admin_user = admin_users(:one) }

  test "requires admin authentication for admin pages" do
    get admin_users_path
    assert_redirected_to new_admin_session_path
  end

  test "loads key admin read-only pages for authenticated admin" do
    sign_in_as_admin(@admin_user)

    get admin_users_path
    assert_response :success

    get admin_organizations_path
    assert_response :success

    get admin_ai_usage_index_path
    assert_response :success

    get admin_review_learning_insights_path
    assert_response :success

    get admin_billing_path
    assert_response :success

    get admin_audit_logs_path
    assert_response :success

    get admin_storage_path
    assert_response :success

    get admin_health_path
    assert_response :success
  end

  test "loads jobs page for authenticated admin" do
    sign_in_as_admin(@admin_user)

    get admin_jobs_path
    assert_response :success
  end
end
