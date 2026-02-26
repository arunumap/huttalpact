require "test_helper"

class Admin::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @admin_user = admin_users(:one) }

  test "new" do
    get new_admin_session_path
    assert_response :success
  end

  test "create with valid credentials" do
    post admin_session_path, params: { email_address: @admin_user.email_address, password: "password" }

    assert_redirected_to admin_root_path
    assert cookies[:admin_session_id]
  end

  test "create with invalid credentials" do
    post admin_session_path, params: { email_address: @admin_user.email_address, password: "wrong" }

    assert_redirected_to new_admin_session_path
    assert_nil cookies[:admin_session_id]
  end

  test "destroy" do
    sign_in_as_admin(@admin_user)

    delete admin_session_path

    assert_redirected_to new_admin_session_path
    assert_empty cookies[:admin_session_id]
  end
end
