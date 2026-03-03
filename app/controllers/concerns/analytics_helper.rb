# frozen_string_literal: true

# Provides a simple interface for tracking GA4 events from controllers.
#
# Usage in controllers:
#   track_analytics_event("sign_up", method: "email")
#   track_analytics_event("purchase", value: 49, currency: "USD")
#
# Events are stored in flash and rendered client-side by the
# shared/_google_analytics partial on the next page load.
module AnalyticsHelper
  extend ActiveSupport::Concern

  private

  def track_analytics_event(event_name, params = {})
    flash[:ga_event] = { event: event_name, params: params }.to_json
  end
end
