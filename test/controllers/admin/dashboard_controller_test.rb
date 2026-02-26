require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  setup { @admin_user = admin_users(:one) }

  test "requires admin authentication" do
    get admin_root_path

    assert_redirected_to new_admin_session_path
  end

  test "shows dashboard for authenticated admin" do
    sign_in_as_admin(@admin_user)

    get admin_root_path

    assert_response :success
    assert_select "h2", text: "Dashboard"
  end
end
