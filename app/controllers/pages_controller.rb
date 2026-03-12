class PagesController < ApplicationController
  ADS_LANDING_SOURCE = "ads_contracts_landing".freeze
  ADS_DMM_MAX_LENGTH = 80
  AD_ATTRIBUTION_QUERY_KEYS = %w[
    utm_source
    utm_medium
    utm_campaign
    utm_term
    utm_content
    gclid
  ].freeze

  allow_unauthenticated_access
  prepend_before_action :resume_session
  rescue_from ActionController::RoutingError, with: :render_not_found

  layout :marketing_layout

  def home
    return redirect_to dashboard_path if authenticated?

    @plan_tiers = PlanCatalogService.active_tiers_for_pricing
  end

  def ads_contracts
    @user = User.new
    @organization_name = nil
    @dmm_term = normalized_dmm_term(params[:utm_term])
    @ads_signup_params = request.query_parameters.slice(*AD_ATTRIBUTION_QUERY_KEYS)
      .merge("source" => ADS_LANDING_SOURCE)
  end

  def privacy
  end

  def solutions
    @solutions = SolutionCatalog.public_solutions
  end

  def solution
    @solution = SolutionCatalog.find_by_slug(params[:slug]) || raise(ActionController::RoutingError, "Not Found")
  end

  def terms
  end

  private

  def marketing_layout
    action_name == "ads_contracts" ? "marketing_funnel" : "marketing"
  end

  def normalized_dmm_term(raw_term)
    term = raw_term.to_s.tr("_", " ").squish
    term = term.gsub(/[^[:alnum:]\s&\/-]/, "").first(ADS_DMM_MAX_LENGTH)&.strip
    term.presence
  end

  def render_not_found
    render file: Rails.public_path.join("404.html"), layout: false, status: :not_found
  end
end
