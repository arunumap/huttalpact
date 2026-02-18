class Settings::InvitationsController < ApplicationController
  include RequireAdminAccess

  before_action :require_admin_access
  before_action :set_invitation, only: %i[destroy resend]

  def create
    if current_organization.at_user_limit?
      redirect_to settings_team_path(tab: "invitations"),
        alert: "You've reached the #{current_organization.plan_display_name} plan limit of #{current_organization.plan_user_limit} team members. <a href='#{pricing_path}' class='underline font-semibold'>Upgrade your plan</a> to invite more."
      return
    end

    # Sanitize role — block owner role
    role = params.dig(:invitation, :role)
    if role == Membership::OWNER_ROLE
      redirect_to settings_team_path(tab: "invitations"), alert: "Cannot assign the owner role via invitation."
      return
    end

    @invitation = current_organization.invitations.build(
      email: invitation_params[:email],
      role: role,
      inviter: Current.user
    )

    if @invitation.save
      InvitationMailer.invite(@invitation).deliver_later
      log_audit(:member_invited, details: "Invited #{@invitation.email} as #{@invitation.role}")
      redirect_to settings_team_path(tab: "invitations"), notice: "Invitation sent to #{@invitation.email}."
    else
      @memberships = current_organization.memberships.ordered.includes(:user)
      @invitations = current_organization.invitations.pending.order(created_at: :desc)
      @tab = "invitations"
      @seats_used = current_organization.seats_used
      @seats_limit = current_organization.plan_user_limit
      flash.now[:alert] = @invitation.errors.full_messages.to_sentence
      render "settings/team/show", status: :unprocessable_entity
    end
  end

  def destroy
    return unless @invitation

    @invitation.destroy!
    log_audit(:invitation_revoked, details: "Revoked invitation for #{@invitation.email}")
    redirect_to settings_team_path(tab: "invitations"), notice: "Invitation for #{@invitation.email} has been revoked."
  end

  def resend
    return unless @invitation

    @invitation.resend!
    InvitationMailer.invite(@invitation).deliver_later
    redirect_to settings_team_path(tab: "invitations"), notice: "Invitation resent to #{@invitation.email}."
  end

  private

  def set_invitation
    @invitation = current_organization.invitations.find_by(id: params[:id])
    unless @invitation
      redirect_to settings_team_path(tab: "invitations"), alert: "Invitation not found."
    end
  end

  def invitation_params
    params.require(:invitation).permit(:email)
  end
end
