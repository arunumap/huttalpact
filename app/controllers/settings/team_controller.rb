class Settings::TeamController < ApplicationController
  include RequireAdminAccess

  before_action :require_admin_access

  def show
    @memberships = current_organization.memberships.ordered.includes(:user)
    @invitations = current_organization.invitations.pending.order(created_at: :desc)
    @invitation = Invitation.new
    @tab = params[:tab].presence || "members"
    @seats_used = current_organization.seats_used
    @seats_limit = current_organization.plan_user_limit
  end
end
