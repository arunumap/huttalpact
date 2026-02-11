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
end
