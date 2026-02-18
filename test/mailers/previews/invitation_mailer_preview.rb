# Preview all emails at http://localhost:3000/rails/mailers/invitation_mailer
class InvitationMailerPreview < ActionMailer::Preview
  # Preview at http://localhost:3000/rails/mailers/invitation_mailer/invite
  def invite
    invitation = Invitation.where(accepted_at: nil).first || Invitation.first
    InvitationMailer.invite(invitation)
  end
end
