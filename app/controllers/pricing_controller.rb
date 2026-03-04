class PricingController < ApplicationController
  allow_unauthenticated_access
  prepend_before_action :resume_session

  layout "pricing"

  def show
    @current_plan = current_organization&.plan || PlanCatalogService.default_plan_slug
    @is_owner = Current.user && current_organization&.owner == Current.user
    @has_subscription = Current.user && current_organization&.active_subscription.present?
    @plan_tiers = PlanCatalogService.active_tiers_for_pricing
  end
end
