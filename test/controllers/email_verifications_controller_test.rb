require "test_helper"

class EmailVerificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(email_verified_at: nil)
  end

  test "show redirects unauthenticated users to sign in" do
    get email_verification_path
    assert_redirected_to new_session_path
  end

  test "show renders for unverified authenticated users" do
    sign_in_as(@user)

    get email_verification_path

    assert_response :success
    assert_match @user.email_address, response.body
  end

  test "show redirects verified users to root" do
    sign_in_as(users(:two))

    get email_verification_path

    assert_redirected_to root_path
  end

  test "create resends verification email for unverified users" do
    sign_in_as(@user)

    assert_enqueued_email_with UserMailer, :email_verification, args: [ @user ] do
      post email_verification_path
    end

    assert_redirected_to email_verification_path
  end

  test "verify marks user as verified and signs in" do
    token = @user.generate_token_for(:email_verification)

    get verify_email_verification_path(token: token)

    assert_redirected_to root_path
    assert @user.reload.email_verified?
    assert cookies[:session_id].present?
  end

  test "verify with invalid token redirects to sign in" do
    get verify_email_verification_path(token: "invalid-token")

    assert_redirected_to new_session_path
  end

  test "verify with expired token redirects to sign in" do
    token = @user.generate_token_for(:email_verification)

    travel 25.hours do
      get verify_email_verification_path(token: token)
    end

    assert_redirected_to new_session_path
  end
end
