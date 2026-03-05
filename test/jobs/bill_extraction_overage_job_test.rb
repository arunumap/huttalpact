require "test_helper"

class BillExtractionOverageJobTest < ActiveJob::TestCase
  test "invokes billing service for unbilled charge" do
    charge = build_charge
    service = Minitest::Mock.new
    service.expect(:call, charge)

    factory = ->(overage_charge) do
      assert_equal charge.id, overage_charge.id
      service
    end

    ExtractionOverageBillingService.stub(:new, factory) do
      BillExtractionOverageJob.perform_now(charge.id)
    end

    service.verify
  end

  test "skips billing when charge is already billed" do
    charge = build_charge
    charge.update!(status: ExtractionOverageCharge::STATUS_BILLED)

    ExtractionOverageBillingService.stub(:new, ->(*) { flunk "service should not be called for billed charges" }) do
      BillExtractionOverageJob.perform_now(charge.id)
    end

    assert_equal ExtractionOverageCharge::STATUS_BILLED, charge.reload.status
  end

  private

  def build_charge
    org = organizations(:one)
    contract = contracts(:hvac_maintenance)
    timestamp = Time.current.beginning_of_day

    ExtractionOverageCharge.create!(
      organization: org,
      contract: contract,
      extraction_period_start_at: timestamp,
      usage_position: rand(100..999),
      overage_cents: 125,
      idempotency_key: "overage-#{org.id}-#{timestamp.utc.iso8601}-#{SecureRandom.hex(4)}"
    )
  end
end
