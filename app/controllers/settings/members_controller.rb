class Settings::MembersController < ApplicationController
  include RequireAdminAccess

  before_action :require_admin_access
  before_action :set_membership
  before_action :authorize_management

  def update
    new_role = params.dig(:membership, :role)

    unless new_role.in?([ Membership::ADMIN_ROLE, Membership::MEMBER_ROLE ])
      redirect_to settings_team_path, alert: "Invalid role. Role not allowed."
      return
    end

    if @membership.update(role: new_role)
      log_audit(:member_role_changed, details: "Changed #{@membership.user.full_name}'s role to #{new_role}")
      redirect_to settings_team_path, notice: "Role updated for #{@membership.user.full_name}."
    else
      redirect_to settings_team_path, alert: "Unable to update role."
    end
  end

  def destroy
    result = MemberRemovalService.call(membership: @membership, performed_by: Current.user)

    if result.success?
      redirect_to settings_team_path, notice: "#{@membership.user.full_name} has been removed from the team."
    else
      redirect_to settings_team_path, alert: result.error
    end
  end

  private

  def set_membership
    @membership = current_organization.memberships.find_by(id: params[:id])
    unless @membership
      redirect_to settings_team_path, alert: "Member not found."
    end
  end

  def authorize_management
    return unless @membership

    if @membership.owner?
      redirect_to settings_team_path, alert: "You cannot manage the organization owner."
      return
    end

    unless @membership.manageable_by?(current_membership)
      redirect_to settings_team_path, alert: "You don't have permission to manage this member."
    end
  end
end
