class Settings::OrganizationController < ApplicationController
  include RequireAdminAccess

  before_action :require_admin_access
  before_action :set_organization

  def show
  end

  def update
    old_name = @organization.name
    old_slug = @organization.slug

    if @organization.update(organization_params)
      details = changes_description(old_name, old_slug)
      log_audit("organization_updated", details: details) if details.present?
      redirect_to settings_organization_path, notice: "Organization updated successfully."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_organization
    @organization = current_organization
  end

  def organization_params
    params.require(:organization).permit(:name, :slug)
  end

  def changes_description(old_name, old_slug)
    changes = []
    changes << "name changed from '#{old_name}' to '#{@organization.name}'" if @organization.name != old_name
    changes << "slug changed from '#{old_slug}' to '#{@organization.slug}'" if @organization.slug != old_slug
    changes.join(", ").presence
  end
end
