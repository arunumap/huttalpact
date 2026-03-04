require "test_helper"

class Admin::AdminUsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin_user = admin_users(:one)
  end

  test "requires admin authentication" do
    get admin_admin_users_path

    assert_redirected_to new_admin_session_path
  end

  test "index renders for admin" do
    sign_in_as_admin(@admin_user)

    get admin_admin_users_path

    assert_response :success
    assert_match @admin_user.email_address, response.body
  end

  test "create admin user" do
    sign_in_as_admin(@admin_user)

    assert_difference "AdminUser.count", 1 do
      post admin_admin_users_path, params: {
        admin_user: {
          email_address: "new-admin@example.com",
          first_name: "New",
          last_name: "Admin",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    created_admin_user = AdminUser.order(:created_at).last
    assert_redirected_to admin_admin_user_path(created_admin_user)
    assert_equal "new-admin@example.com", created_admin_user.email_address
  end

  test "update admin user without changing password" do
    sign_in_as_admin(@admin_user)

    patch admin_admin_user_path(@admin_user), params: {
      admin_user: {
        first_name: "Updated",
        password: "",
        password_confirmation: ""
      }
    }

    assert_redirected_to admin_admin_user_path(@admin_user)
    assert_equal "Updated", @admin_user.reload.first_name
  end

  test "destroy another admin user" do
    sign_in_as_admin(@admin_user)

    removable_admin = AdminUser.create!(
      email_address: "remove-me@example.com",
      first_name: "Remove",
      last_name: "Me",
      password: "password123",
      password_confirmation: "password123"
    )

    assert_difference "AdminUser.count", -1 do
      delete admin_admin_user_path(removable_admin)
    end

    assert_redirected_to admin_admin_users_path
  end

  test "cannot destroy current signed in admin user" do
    sign_in_as_admin(@admin_user)

    assert_no_difference "AdminUser.count" do
      delete admin_admin_user_path(@admin_user)
    end

    assert_redirected_to admin_admin_users_path
    follow_redirect!
    assert_match "cannot delete your own admin account", response.body.downcase
  end
end
