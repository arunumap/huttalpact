class InvitationMailer < ApplicationMailer
  def invite(invitation)
    @invitation = invitation
    @organization = invitation.organization
    @inviter = invitation.inviter
    @signup_url = new_registration_url(token: invitation.token)

    mail(to: invitation.email, subject: "You're invited to join #{@organization.name} on HuttalPact")
  end
end
