class ExtractionOverageBillingService
  class BillingError < StandardError; end

  def initialize(overage_charge)
    @overage_charge = overage_charge
    @organization = overage_charge.organization
  end

  def call
    return @overage_charge if @overage_charge.billed?

    validate_billable_context!

    invoice_item = Stripe::InvoiceItem.create(
      stripe_invoice_item_payload,
      { idempotency_key: @overage_charge.idempotency_key }
    )

    @overage_charge.update!(
      status: ExtractionOverageCharge::STATUS_BILLED,
      stripe_invoice_item_id: invoice_item.id,
      billed_at: Time.current,
      error_message: nil
    )

    @overage_charge
  rescue BillingError, Stripe::StripeError => e
    @overage_charge.update!(
      status: ExtractionOverageCharge::STATUS_FAILED,
      error_message: e.message.to_s.truncate(500)
    )
    raise
  end

  private

  def validate_billable_context!
    raise BillingError, "Missing Stripe customer for organization #{@organization.id}" if stripe_customer_id.blank?

    subscription = @organization.active_subscription
    raise BillingError, "No active subscription for organization #{@organization.id}" unless subscription
    raise BillingError, "Subscription is pending cancellation for organization #{@organization.id}" if @organization.pending_cancellation?

    unless subscription.status.to_s.in?(%w[active trialing])
      raise BillingError, "Subscription status #{subscription.status} is not billable for organization #{@organization.id}"
    end
  end

  def stripe_customer_id
    @organization.pay_customers&.first&.processor_id
  end

  def stripe_invoice_item_payload
    {
      customer: stripe_customer_id,
      amount: @overage_charge.overage_cents,
      currency: "usd",
      description: "AI extraction overage charge",
      metadata: {
        organization_id: @organization.id,
        contract_id: @overage_charge.contract_id,
        plan_slug: @organization.plan,
        extraction_period_start: @overage_charge.extraction_period_start_at.iso8601,
        usage_position: @overage_charge.usage_position
      }
    }
  end
end
