require "test_helper"

class InvitationTest < ActiveSupport::TestCase
  test "valid invitation" do
    invitation = Invitation.new(
      organization: organizations(:one),
      inviter: users(:one),
      email: "new@example.com",
      role: Membership::MEMBER_ROLE
    )

    assert invitation.valid?
    assert invitation.token.present?
    assert invitation.expires_at.present?
  end

  test "requires unique pending email per organization" do
    invitation = Invitation.new(
      organization: organizations(:one),
      inviter: users(:one),
      email: "invitee@example.com",
      role: Membership::MEMBER_ROLE
    )

    assert_not invitation.valid?
    assert_includes invitation.errors[:email], "has already been invited"
  end

  test "cannot invite someone who is already a member" do
    invitation = Invitation.new(
      organization: organizations(:two),
      inviter: users(:two),
      email: users(:three).email_address, # carol is already a member (admin) of org two
      role: Membership::MEMBER_ROLE
    )

    assert_not invitation.valid?
    assert_includes invitation.errors[:email], "is already a member of this organization"
  end

  test "allows inviting same email to different organizations" do
    invitation = Invitation.new(
      organization: organizations(:one),
      inviter: users(:one),
      email: "newperson@example.com",
      role: Membership::MEMBER_ROLE
    )
    assert invitation.valid?
  end

  test "resend! refreshes expires_at" do
    invitation = invitations(:pending)
    old_expires = invitation.expires_at
    travel_to 1.day.from_now do
      invitation.resend!
      assert invitation.expires_at > old_expires
    end
  end

  test "expired? returns true for expired invitations" do
    invitation = invitations(:pending)
    travel_to 15.days.from_now do
      assert invitation.expired?
    end
  end

  test "expired? returns false for non-expired invitations" do
    invitation = invitations(:pending)
    assert_not invitation.expired?
  end
end
