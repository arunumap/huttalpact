# frozen_string_literal: true

module PaySubscriptionCallbacks
  extend ActiveSupport::Concern

  included do
    after_commit :sync_owner_plan, on: %i[create update destroy]
  end

  private

  def sync_owner_plan
    owner = customer&.owner
    return unless owner.is_a?(Organization)

    owner.sync_plan_from_subscription!

    if owner.pending_downgrade? && owner.plan == owner.pending_plan
      owner.clear_pending_downgrade!
    end
  rescue => e
    Rails.logger.error("Pay subscription sync error: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry) && Sentry.initialized?
  end
end
