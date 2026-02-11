class PricingController < ApplicationController
  allow_unauthenticated_access
  prepend_before_action :resume_session

  layout "pricing"

  def show
    @current_plan = current_organization&.plan || "free"
    @is_owner = Current.user && current_organization&.owner == Current.user
  end
end
