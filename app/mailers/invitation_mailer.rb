class InvitationMailer < ApplicationMailer
  def invite(invitation)
    @invitation = invitation
    @organization = invitation.organization
    @inviter = invitation.inviter
    @accept_url = accept_invitation_url(token: invitation.token)

    mail(to: invitation.email, subject: "You're invited to join #{@organization.name} on PactBadger")
  end
end
