class OrphanedAccountsController < ApplicationController
  skip_before_action :set_tenant
  skip_before_action :set_unread_alert_count
  skip_before_action :redirect_to_onboarding

  layout "auth"

  def show
    redirect_to root_path if Current.user&.organizations&.exists?
  end
end
