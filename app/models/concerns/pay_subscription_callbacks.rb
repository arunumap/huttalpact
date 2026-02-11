# frozen_string_literal: true

module PaySubscriptionCallbacks
  extend ActiveSupport::Concern

  included do
    after_commit :sync_owner_plan, on: %i[create update destroy]
  end

  private

  def sync_owner_plan
    owner = customer&.owner
    owner&.sync_plan_from_subscription! if owner.is_a?(Organization)
  rescue => e
    Rails.logger.error("Pay subscription sync error: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry) && Sentry.initialized?
  end
end
