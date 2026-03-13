class InvitationAcceptancesController < ApplicationController
  allow_unauthenticated_access
  allow_unverified_access
  skip_before_action :set_tenant
  skip_before_action :set_unread_alert_count
  skip_before_action :redirect_to_onboarding

  before_action :try_resume_session
  before_action :set_invitation

  def show
    if Current.user
      accept_for_authenticated_user
    elsif User.exists?(email_address: @invitation.email)
      accept_for_existing_user
    else
      redirect_to new_registration_path(token: @invitation.token)
    end
  end

  private

  def set_invitation
    @invitation = Invitation.pending.find_by(token: params[:token])
    return if @invitation

    redirect_to root_path, alert: "This invitation link is invalid or has expired."
  end

  def accept_for_authenticated_user
    unless Current.user.email_address.downcase == @invitation.email.downcase
      redirect_to root_path, alert: "This invitation was sent to #{@invitation.email}. Please sign in with that account to accept."
      return
    end

    create_membership_for(Current.user)
    @invitation.accept!
    session[:current_organization_id] = @invitation.organization_id
    redirect_to dashboard_path, notice: "You've joined #{@invitation.organization.name}."
  end

  def accept_for_existing_user
    user = User.find_by!(email_address: @invitation.email)
    create_membership_for(user)
    @invitation.accept!
    redirect_to new_session_path, notice: "You've joined #{@invitation.organization.name}. Please sign in to continue."
  end

  def create_membership_for(user)
    user.memberships.find_or_create_by!(organization: @invitation.organization) do |membership|
      membership.role = @invitation.role
    end
    user.verify_email! unless user.email_verified?
  end

  def try_resume_session
    resume_session
  end
end
