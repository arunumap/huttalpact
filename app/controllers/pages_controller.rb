class PagesController < ApplicationController
  ADS_LANDING_SOURCE = "ads_contracts_landing".freeze
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
    @user = User.new
    @organization_name = nil
    @ads_signup_params = request.query_parameters.slice(*AD_ATTRIBUTION_QUERY_KEYS)
      .merge("source" => ADS_LANDING_SOURCE)
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
