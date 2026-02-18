require "test_helper"

class Settings::ProfileControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one) # Alice, owner of org one
  end

  # === Access ===

  test "authenticated user can view profile page" do
    sign_in_as @user
    get settings_profile_path
    assert_response :success
    assert_match "Profile", response.body
    assert_match @user.first_name, response.body
    assert_match @user.email_address, response.body
  end

  test "unauthenticated user redirected to login" do
    get settings_profile_path
    assert_redirected_to new_session_path
  end

  # === Profile updates ===

  test "can update name" do
    sign_in_as @user
    patch settings_profile_path, params: { user: { first_name: "Alicia", last_name: "Jones", email_address: @user.email_address } }
    assert_redirected_to settings_profile_path
    assert_equal "Profile updated successfully.", flash[:notice]
    @user.reload
    assert_equal "Alicia", @user.first_name
    assert_equal "Jones", @user.last_name
  end

  test "can update email" do
    sign_in_as @user
    patch settings_profile_path, params: { user: { first_name: @user.first_name, last_name: @user.last_name, email_address: "newalice@example.com" } }
    assert_redirected_to settings_profile_path
    @user.reload
    assert_equal "newalice@example.com", @user.email_address
  end

  test "invalid email shows errors" do
    sign_in_as @user
    patch settings_profile_path, params: { user: { first_name: @user.first_name, last_name: @user.last_name, email_address: "" } }
    assert_response :unprocessable_entity
    assert_match "can&#39;t be blank", response.body
  end

  test "duplicate email shows errors" do
    sign_in_as @user
    patch settings_profile_path, params: { user: { first_name: @user.first_name, last_name: @user.last_name, email_address: users(:two).email_address } }
    assert_response :unprocessable_entity
  end

  test "profile update creates audit log" do
    sign_in_as @user
    assert_difference "AuditLog.count", 1 do
      patch settings_profile_path, params: { user: { first_name: "Alicia", last_name: @user.last_name, email_address: @user.email_address } }
    end
    assert_equal "profile_updated", AuditLog.last.action
  end

  # === Password changes ===

  test "can change password with correct current password" do
    sign_in_as @user
    patch settings_profile_path, params: {
      password_change: {
        current_password: "password",
        password: "newpassword123",
        password_confirmation: "newpassword123"
      }
    }
    assert_redirected_to settings_profile_path
    assert_equal "Password changed successfully.", flash[:notice]
    # Verify new password works
    assert User.authenticate_by(email_address: @user.email_address, password: "newpassword123")
  end

  test "wrong current password fails" do
    sign_in_as @user
    patch settings_profile_path, params: {
      password_change: {
        current_password: "wrongpassword",
        password: "newpassword123",
        password_confirmation: "newpassword123"
      }
    }
    assert_response :unprocessable_entity
    assert_match "Current password is incorrect", response.body
  end

  test "password too short fails" do
    sign_in_as @user
    patch settings_profile_path, params: {
      password_change: {
        current_password: "password",
        password: "short",
        password_confirmation: "short"
      }
    }
    assert_response :unprocessable_entity
  end

  test "password confirmation mismatch fails" do
    sign_in_as @user
    patch settings_profile_path, params: {
      password_change: {
        current_password: "password",
        password: "newpassword123",
        password_confirmation: "differentpassword"
      }
    }
    assert_response :unprocessable_entity
  end

  test "password change destroys other sessions" do
    sign_in_as @user
    # Create an additional session to simulate another device
    other_session = @user.sessions.create!
    assert @user.sessions.count >= 2

    patch settings_profile_path, params: {
      password_change: {
        current_password: "password",
        password: "newpassword123",
        password_confirmation: "newpassword123"
      }
    }
    assert_redirected_to settings_profile_path
    # The other session should be destroyed, only current one remains
    assert_not Session.exists?(other_session.id)
    assert_equal 1, @user.sessions.reload.count
  end

  test "password change creates audit log" do
    sign_in_as @user
    assert_difference "AuditLog.count", 1 do
      patch settings_profile_path, params: {
        password_change: {
          current_password: "password",
          password: "newpassword123",
          password_confirmation: "newpassword123"
        }
      }
    end
    assert_equal "password_changed", AuditLog.last.action
  end

  # === Any role can access ===

  test "member can view and update profile" do
    member = users(:four) # Dave, member of org two
    sign_in_as member
    get settings_profile_path
    assert_response :success

    patch settings_profile_path, params: { user: { first_name: "David", last_name: member.last_name, email_address: member.email_address } }
    assert_redirected_to settings_profile_path
    assert_equal "David", member.reload.first_name
  end
end
