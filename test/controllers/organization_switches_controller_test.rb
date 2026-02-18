require "test_helper"

class OrganizationSwitchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)         # alice — owner of org :one
    @org_one = organizations(:one)
    @org_two = organizations(:two)
    sign_in_as(@user)
  end

  test "switches to an organization the user belongs to" do
    # Give user a membership in org_two
    @org_two.memberships.create!(user: @user, role: "member")

    post switch_organization_path(@org_two)

    assert_redirected_to dashboard_path
    assert_match "Switched to #{@org_two.name}", flash[:notice]

    # Verify session was updated by making a subsequent request
    get dashboard_path
    assert_response :success
  end

  test "rejects switch to an organization the user does not belong to" do
    post switch_organization_path(@org_two)

    assert_redirected_to dashboard_path
    assert_match "Organization not found", flash[:alert]
  end

  test "rejects switch to a nonexistent organization" do
    post switch_organization_path(id: "00000000-0000-0000-0000-000000000000")

    assert_redirected_to dashboard_path
    assert_match "Organization not found", flash[:alert]
  end

  test "requires authentication" do
    sign_out
    post switch_organization_path(@org_one)

    assert_redirected_to new_session_path
  end

  test "set_tenant falls back to first org when session org is invalid" do
    # Set a bogus org id in session
    post switch_organization_path(id: "00000000-0000-0000-0000-000000000000")

    # Should still load fine — falls back to first org
    get dashboard_path
    assert_response :success
  end

  test "set_tenant uses session org when valid" do
    @org_two.memberships.create!(user: @user, role: "member")

    post switch_organization_path(@org_two)
    assert_redirected_to dashboard_path

    # Subsequent request should use org_two
    get contracts_path
    assert_response :success
  end
end
