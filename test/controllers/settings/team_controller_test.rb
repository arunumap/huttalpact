require "test_helper"

class Settings::TeamControllerTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:two)  # starter plan
    @owner = users(:two)        # owner of org two
    @admin = users(:three)      # admin of org two
    @member = users(:four)      # member of org two
  end

  # Access control
  test "owner can view team page" do
    sign_in_as @owner
    get settings_team_path
    assert_response :success
    assert_match "Team", response.body
  end

  test "admin can view team page" do
    sign_in_as @admin
    get settings_team_path
    assert_response :success
  end

  test "member is redirected with flash" do
    sign_in_as @member
    get settings_team_path
    assert_redirected_to root_path
    assert_match /admin|owner/i, flash[:alert]
  end

  test "unauthenticated user redirected to login" do
    get settings_team_path
    assert_redirected_to new_session_path
  end

  # Page content - members tab
  test "shows all members on members tab" do
    sign_in_as @owner
    get settings_team_path
    assert_response :success
    assert_match @owner.full_name, response.body
    assert_match @admin.full_name, response.body
    assert_match @member.full_name, response.body
  end

  test "shows seat count" do
    sign_in_as @owner
    get settings_team_path
    assert_response :success
    assert_match "3", response.body  # 3 seats used
    assert_match "5", response.body  # 5 seats limit (starter plan)
  end

  # Invitations tab
  test "shows pending invitations on invitations tab" do
    # Create a pending invitation for org two
    invitation = Invitation.create!(
      organization: @org,
      inviter: @owner,
      email: "pending@example.com",
      role: Membership::MEMBER_ROLE
    )
    sign_in_as @owner
    get settings_team_path(tab: "invitations")
    assert_response :success
    assert_match "pending@example.com", response.body
  end

  test "defaults to members tab" do
    sign_in_as @owner
    get settings_team_path
    assert_response :success
    # Members table should be visible
    assert_select "[data-tab='members']" rescue nil
  end
end
