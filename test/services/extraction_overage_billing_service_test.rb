require "test_helper"
require "ostruct"

class ExtractionOverageBillingServiceTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
    @org.update!(plan: "starter")
    @contract = contracts(:hvac_maintenance)
    @charge = ExtractionOverageCharge.create!(
      organization: @org,
      contract: @contract,
      extraction_period_start_at: Time.current.beginning_of_day,
      usage_position: 51,
      overage_cents: 125,
      idempotency_key: "overage-#{@org.id}-#{Time.current.beginning_of_day.utc.iso8601}-51"
    )
  end

  test "creates Stripe invoice item and marks charge billed" do
    create_active_subscription_for(@org)
    fake_invoice_item = OpenStruct.new(id: "ii_test_123")

    Stripe::InvoiceItem.stub(:create, fake_invoice_item) do
      ExtractionOverageBillingService.new(@charge).call
    end

    @charge.reload
    assert_equal ExtractionOverageCharge::STATUS_BILLED, @charge.status
    assert_equal "ii_test_123", @charge.stripe_invoice_item_id
    assert_not_nil @charge.billed_at
  end

  test "marks charge failed when stripe customer is missing" do
    assert_raises ExtractionOverageBillingService::BillingError do
      ExtractionOverageBillingService.new(@charge).call
    end

    @charge.reload
    assert_equal ExtractionOverageCharge::STATUS_FAILED, @charge.status
    assert_match "Missing Stripe customer", @charge.error_message
  end

  test "marks charge failed when subscription is pending cancellation" do
    create_active_subscription_for(@org, ends_at: 2.days.from_now)

    assert_raises ExtractionOverageBillingService::BillingError do
      ExtractionOverageBillingService.new(@charge).call
    end

    @charge.reload
    assert_equal ExtractionOverageCharge::STATUS_FAILED, @charge.status
    assert_match "pending cancellation", @charge.error_message
  end

  private

  def create_active_subscription_for(org, ends_at: nil)
    customer = org.set_payment_processor(:stripe)
    customer.update!(processor_id: "cus_service_overage_#{SecureRandom.hex(4)}")

    Pay::Stripe::Subscription.create!(
      customer: customer,
      processor_id: "sub_service_overage_#{SecureRandom.hex(4)}",
      processor_plan: "price_overage_service",
      name: "default",
      status: "active",
      ends_at: ends_at
    )
  end
end
