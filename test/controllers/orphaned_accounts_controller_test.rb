require "test_helper"

class OrphanedAccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @orphaned_user = User.create!(
      email_address: "orphaned@example.com",
      password: "password123",
      first_name: "Orphaned",
      terms_accepted: "1",
      email_verified_at: Time.current
    )
    @orphaned_user.update_column(:orphaned_at, Time.current)
  end

  test "shows orphaned account page for user with no organizations" do
    sign_in_as(@orphaned_user)
    get orphaned_account_path
    assert_response :success
    assert_select "p", /no longer associated with any organization/
    assert_select "a[href='mailto:support@pactbadger.com']"
  end

  test "redirects to root if user has organizations" do
    user = users(:one)
    sign_in_as(user)
    get orphaned_account_path
    assert_redirected_to root_path
  end

  test "redirects orphaned user to orphaned account page from dashboard" do
    sign_in_as(@orphaned_user)
    get dashboard_path
    assert_redirected_to orphaned_account_path
  end

  test "orphaned user is not stuck in redirect loop" do
    sign_in_as(@orphaned_user)

    get dashboard_path
    assert_redirected_to orphaned_account_path

    follow_redirect!
    assert_response :success
    assert_select "p", /no longer associated with any organization/
  end

  test "orphaned user can sign out from orphaned account page" do
    sign_in_as(@orphaned_user)
    delete session_path
    assert_redirected_to new_session_path
  end
end
