require "test_helper"

class InvitationAcceptancesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @invitation = invitations(:pending)
    @organization = organizations(:one)
  end

  # --- New user (no account) → redirect to registration ---

  test "new user is redirected to registration with token" do
    get accept_invitation_path(token: @invitation.token)

    assert_redirected_to new_registration_path(token: @invitation.token)
  end

  # --- Existing user, not logged in → membership created, redirect to sign-in ---

  test "existing user not logged in gets membership and redirected to sign in" do
    # Create a user with the same email as the invitation but no membership in org one
    existing_user = User.create!(
      email_address: @invitation.email,
      password: "password123",
      first_name: "Existing",
      last_name: "User"
    )

    assert_difference "Membership.count", 1 do
      get accept_invitation_path(token: @invitation.token)
    end

    assert_redirected_to new_session_path
    assert_match "You've joined", flash[:notice]

    membership = existing_user.memberships.find_by(organization: @organization)
    assert_not_nil membership
    assert_equal @invitation.role, membership.role
    assert @invitation.reload.accepted_at.present?
  end

  # --- Logged-in user, email matches → membership created, redirect to dashboard ---

  test "logged-in user with matching email gets membership" do
    user = User.create!(
      email_address: @invitation.email,
      password: "password123",
      first_name: "Invited",
      last_name: "Person"
    )
    # Give user an org so sign_in_as works (needs at least one org for session)
    other_org = Organization.create!(name: "Other Org", onboarding_completed_at: Time.current, onboarding_step: 2)
    other_org.memberships.create!(user: user, role: "owner")
    sign_in_as(user)

    assert_difference "Membership.count", 1 do
      get accept_invitation_path(token: @invitation.token)
    end

    assert_redirected_to dashboard_path
    assert_match "You've joined", flash[:notice]

    membership = user.memberships.find_by(organization: @organization)
    assert_not_nil membership
    assert_equal @invitation.role, membership.role
    assert @invitation.reload.accepted_at.present?
  end

  # --- Logged-in user, email mismatch → rejected ---

  test "logged-in user with different email is rejected" do
    sign_in_as(users(:one)) # alice@example.com, invitation is for invitee@example.com

    assert_no_difference "Membership.count" do
      get accept_invitation_path(token: @invitation.token)
    end

    assert_redirected_to root_path
    assert_match "sent to #{@invitation.email}", flash[:alert]
    assert_nil @invitation.reload.accepted_at
  end

  # --- Invalid / expired token ---

  test "invalid token redirects with error" do
    get accept_invitation_path(token: "bogus-token")

    assert_redirected_to root_path
    assert_match "invalid or has expired", flash[:alert]
  end

  test "expired invitation redirects with error" do
    @invitation.update!(expires_at: 1.day.ago)

    get accept_invitation_path(token: @invitation.token)

    assert_redirected_to root_path
    assert_match "invalid or has expired", flash[:alert]
  end

  test "already accepted invitation redirects with error" do
    @invitation.accept!

    get accept_invitation_path(token: @invitation.token)

    assert_redirected_to root_path
    assert_match "invalid or has expired", flash[:alert]
  end

  # --- Idempotent: already a member ---

  test "does not duplicate membership if user is already a member" do
    user = User.create!(
      email_address: @invitation.email,
      password: "password123",
      first_name: "Invited",
      last_name: "Person"
    )
    @organization.memberships.create!(user: user, role: "member")
    other_org = Organization.create!(name: "Other Org", onboarding_completed_at: Time.current, onboarding_step: 2)
    other_org.memberships.create!(user: user, role: "owner")
    sign_in_as(user)

    assert_no_difference "Membership.count" do
      get accept_invitation_path(token: @invitation.token)
    end

    assert_redirected_to dashboard_path
    assert @invitation.reload.accepted_at.present?
  end
end
