require "test_helper"

class ReconcileExtractionOverageChargesJobTest < ActiveJob::TestCase
  test "enqueues billing jobs for stale pending and failed charges" do
    stale_pending = build_charge(status: ExtractionOverageCharge::STATUS_PENDING, usage_position: 51)
    stale_pending.update_columns(created_at: 1.hour.ago, updated_at: 1.hour.ago)

    stale_failed = build_charge(status: ExtractionOverageCharge::STATUS_FAILED, usage_position: 52)
    stale_failed.update_columns(created_at: 1.hour.ago, updated_at: 1.hour.ago)

    fresh_pending = build_charge(status: ExtractionOverageCharge::STATUS_PENDING, usage_position: 53)

    assert_enqueued_jobs 2, only: BillExtractionOverageJob do
      ReconcileExtractionOverageChargesJob.perform_now
    end

    enqueued_ids = enqueued_jobs.select { |job| job[:job] == BillExtractionOverageJob }.map { |job| job[:args].first }
    assert_includes enqueued_ids, stale_pending.id
    assert_includes enqueued_ids, stale_failed.id
    assert_not_includes enqueued_ids, fresh_pending.id
  end

  private

  def build_charge(status:, usage_position:)
    org = organizations(:one)
    contract = contracts(:hvac_maintenance)
    timestamp = Time.current.beginning_of_day

    ExtractionOverageCharge.create!(
      organization: org,
      contract: contract,
      extraction_period_start_at: timestamp,
      usage_position: usage_position,
      overage_cents: 125,
      status: status,
      idempotency_key: "overage-#{org.id}-#{timestamp.utc.iso8601}-#{usage_position}-#{SecureRandom.hex(4)}"
    )
  end
end
