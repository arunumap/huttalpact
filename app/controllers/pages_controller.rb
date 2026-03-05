class PagesController < ApplicationController
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

  layout :marketing_layout

  def home
    redirect_to dashboard_path if authenticated?
  end

  def ads_contracts
    @ads_signup_params = request.query_parameters.slice(*AD_ATTRIBUTION_QUERY_KEYS)
      .merge("source" => "ads_contracts_landing")
  end

  def privacy
  end

  def leases
  end

  def terms
  end

  private

  def marketing_layout
    action_name == "ads_contracts" ? "marketing_funnel" : "marketing"
  end
end
