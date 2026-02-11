require "test_helper"

class InvitationMailerTest < ActionMailer::TestCase
  test "invite" do
    invitation = invitations(:pending)
    mail = InvitationMailer.invite(invitation)

    assert_equal "You're invited to join #{invitation.organization.name} on HuttalPact", mail.subject
    assert_equal [ invitation.email ], mail.to
    assert_match invitation.token, mail.body.encoded
  end
end
