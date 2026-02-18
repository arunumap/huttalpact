require "test_helper"

class Settings::InvitationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:two)  # starter plan (5 seats, 3 used)
    @owner = users(:two)
    @admin = users(:three)
    @member = users(:four)
  end

  # Create invitation — access control

  test "owner can send invitation" do
    sign_in_as @owner
    assert_difference "Invitation.count", 1 do
      post settings_invitations_path, params: {
        invitation: { email: "newbie@example.com", role: "member" }
      }
    end
    assert_response :redirect
  end

  test "admin can send invitation" do
    sign_in_as @admin
    assert_difference "Invitation.count", 1 do
      post settings_invitations_path, params: {
        invitation: { email: "newbie2@example.com", role: "member" }
      }
    end
  end

  test "member cannot send invitation" do
    sign_in_as @member
    assert_no_difference "Invitation.count" do
      post settings_invitations_path, params: {
        invitation: { email: "newbie3@example.com", role: "member" }
      }
    end
    assert_redirected_to root_path
  end

  # Create invitation — validations

  test "cannot invite with owner role" do
    sign_in_as @owner
    assert_no_difference "Invitation.count" do
      post settings_invitations_path, params: {
        invitation: { email: "wannabe-owner@example.com", role: "owner" }
      }
    end
  end

  test "cannot invite existing member" do
    sign_in_as @owner
    assert_no_difference "Invitation.count" do
      post settings_invitations_path, params: {
        invitation: { email: @admin.email_address, role: "member" }
      }
    end
  end

  test "cannot invite with invalid email" do
    sign_in_as @owner
    assert_no_difference "Invitation.count" do
      post settings_invitations_path, params: {
        invitation: { email: "not-an-email", role: "member" }
      }
    end
  end

  # Seat limit enforcement
  test "cannot invite when at seat limit" do
    @org.update!(plan: "free") # free plan: 1 seat, already 3 members
    sign_in_as @owner
    assert_no_difference "Invitation.count" do
      post settings_invitations_path, params: {
        invitation: { email: "toomany@example.com", role: "member" }
      }
    end
    assert_match /limit|upgrade/i, flash[:alert]
  end

  # Email delivery

  test "sends invitation email" do
    sign_in_as @owner
    assert_enqueued_emails 1 do
      post settings_invitations_path, params: {
        invitation: { email: "emailtest@example.com", role: "member" }
      }
    end
  end

  # Audit log

  test "invitation creates audit log entry" do
    sign_in_as @owner
    assert_difference "AuditLog.unscoped.count", 1 do
      post settings_invitations_path, params: {
        invitation: { email: "auditlog@example.com", role: "member" }
      }
    end
    audit = AuditLog.unscoped.order(created_at: :desc).first
    assert_equal "member_invited", audit.action
  end

  # Revoke invitation

  test "owner can revoke pending invitation" do
    invitation = Invitation.create!(
      organization: @org,
      inviter: @owner,
      email: "revokeme@example.com",
      role: Membership::MEMBER_ROLE
    )
    sign_in_as @owner
    assert_difference "Invitation.count", -1 do
      delete settings_invitation_path(invitation)
    end
  end

  test "admin can revoke pending invitation" do
    invitation = Invitation.create!(
      organization: @org,
      inviter: @owner,
      email: "revokeme2@example.com",
      role: Membership::MEMBER_ROLE
    )
    sign_in_as @admin
    assert_difference "Invitation.count", -1 do
      delete settings_invitation_path(invitation)
    end
  end

  test "member cannot revoke invitation" do
    invitation = Invitation.create!(
      organization: @org,
      inviter: @owner,
      email: "revokeme3@example.com",
      role: Membership::MEMBER_ROLE
    )
    sign_in_as @member
    assert_no_difference "Invitation.count" do
      delete settings_invitation_path(invitation)
    end
    assert_redirected_to root_path
  end

  test "revoke creates audit log entry" do
    invitation = Invitation.create!(
      organization: @org,
      inviter: @owner,
      email: "revokeaudit@example.com",
      role: Membership::MEMBER_ROLE
    )
    sign_in_as @owner
    assert_difference "AuditLog.unscoped.count", 1 do
      delete settings_invitation_path(invitation)
    end
    audit = AuditLog.unscoped.order(created_at: :desc).first
    assert_equal "invitation_revoked", audit.action
  end

  # Resend invitation

  test "owner can resend invitation" do
    invitation = Invitation.create!(
      organization: @org,
      inviter: @owner,
      email: "resendme@example.com",
      role: Membership::MEMBER_ROLE
    )
    sign_in_as @owner
    old_expires = invitation.expires_at

    travel_to 1.day.from_now do
      assert_enqueued_emails 1 do
        post resend_settings_invitation_path(invitation)
      end
    end
    assert_response :redirect
    assert invitation.reload.expires_at > old_expires
  end

  test "member cannot resend invitation" do
    invitation = Invitation.create!(
      organization: @org,
      inviter: @owner,
      email: "noresend@example.com",
      role: Membership::MEMBER_ROLE
    )
    sign_in_as @member
    post resend_settings_invitation_path(invitation)
    assert_redirected_to root_path
  end

  # Auth
  test "requires authentication" do
    post settings_invitations_path, params: {
      invitation: { email: "noauth@example.com", role: "member" }
    }
    assert_redirected_to new_session_path
  end

  # Cross-org protection
  test "cannot revoke invitation from another org" do
    # Create invitation in org one
    invitation = Invitation.create!(
      organization: organizations(:one),
      inviter: users(:one),
      email: "crossorg@example.com",
      role: Membership::MEMBER_ROLE
    )
    sign_in_as @owner  # owner of org two
    assert_no_difference "Invitation.count" do
      delete settings_invitation_path(invitation)
    end
  end
end
