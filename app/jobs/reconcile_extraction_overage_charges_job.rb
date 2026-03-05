class ReconcileExtractionOverageChargesJob < ApplicationJob
  queue_as :default

  def perform
    ExtractionOverageCharge.pending_or_failed.stale.find_each do |overage_charge|
      BillExtractionOverageJob.perform_later(overage_charge.id)
    end
  end
end
