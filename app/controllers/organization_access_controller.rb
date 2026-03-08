class OrganizationAccessController < ApplicationController
  layout "auth"

  skip_before_action :set_tenant
  skip_before_action :set_unread_alert_count
  skip_before_action :redirect_to_onboarding

  before_action :ensure_orgless_user

  def show
  end

  def destroy
    OrphanedUserDeletionService.new(Current.user).delete!

    session.delete(:current_organization_id)
    session.delete(:return_to_after_authenticating)
    Current.session = nil
    cookies.delete(:session_id)

    redirect_to root_path, notice: "Your account has been deleted."
  rescue ArgumentError, ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey => e
    Rails.logger.error("OrganizationAccessController#destroy failed for user #{Current.user&.id}: #{e.message}")
    redirect_to organization_access_path, alert: "We couldn't delete your account right now. Please contact support@pactbadger.com."
  end

  private

  def ensure_orgless_user
    return if Current.user.without_organizations?

    redirect_to root_path
  end
end
