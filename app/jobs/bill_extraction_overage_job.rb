class BillExtractionOverageJob < ApplicationJob
  queue_as :default

  retry_on Stripe::APIConnectionError, Stripe::RateLimitError, Stripe::APIError, wait: :polynomially_longer, attempts: 5
  discard_on Stripe::InvalidRequestError
  discard_on ExtractionOverageBillingService::BillingError
  discard_on ActiveRecord::RecordNotFound

  def perform(overage_charge_id)
    overage_charge = ExtractionOverageCharge.find(overage_charge_id)
    return if overage_charge.billed?

    ExtractionOverageBillingService.new(overage_charge).call
  rescue => e
    Rails.logger.error("Failed to bill extraction overage charge #{overage_charge_id}: #{e.class} #{e.message}")
    Sentry.capture_exception(e, extra: { overage_charge_id: overage_charge_id }) if defined?(Sentry) && Sentry.initialized?
    raise
  end
end
