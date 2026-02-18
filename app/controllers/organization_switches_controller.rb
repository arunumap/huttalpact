class OrganizationSwitchesController < ApplicationController
  skip_before_action :set_tenant
  skip_before_action :set_unread_alert_count
  skip_before_action :redirect_to_onboarding

  def create
    organization = Current.user.organizations.find_by(id: params[:id])

    unless organization
      redirect_to dashboard_path, alert: "Organization not found."
      return
    end

    session[:current_organization_id] = organization.id
    redirect_to dashboard_path, notice: "Switched to #{organization.name}."
  end
end
