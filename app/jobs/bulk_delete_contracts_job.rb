class BulkDeleteContractsJob < ApplicationJob
  include ActionView::RecordIdentifier

  queue_as :default

  def perform(operation_id, contract_ids)
    operation = BulkDeleteOperation.find(operation_id)

    operation.update!(
      status: BulkDeleteOperation::STATUS_PROCESSING,
      processed_count: 0,
      deleted_count: 0,
      failed_count: 0,
      error_message: nil
    )
    broadcast_status(operation)

    deleted_count = 0
    failed_count = 0
    processed_count = 0

    Array(contract_ids).compact_blank.uniq.each do |contract_id|
      contract = Contract.find_by(id: contract_id, organization_id: operation.organization_id)
      unless contract
        processed_count += 1
        failed_count += 1
        update_progress(operation, processed_count:, deleted_count:, failed_count:)
        next
      end

      contract_title = contract.title
      AuditLog.create!(
        organization: operation.organization,
        user: operation.user,
        contract: contract,
        action: "deleted",
        details: "Deleted contract via bulk action: #{contract_title}"
      )

      contract.destroy!
      deleted_count += 1
      processed_count += 1

      broadcast_contract_removed(operation.organization_id, contract)
      update_progress(operation, processed_count:, deleted_count:, failed_count:)
    rescue StandardError => e
      failed_count += 1
      processed_count += 1
      operation.update!(error_message: e.message.to_s.truncate(500))
      update_progress(operation, processed_count:, deleted_count:, failed_count:)

      Rails.logger.error("Bulk delete failed for contract #{contract_id}: #{e.message}")
      Sentry.capture_exception(e) if Sentry.initialized?
    end

    final_status =
      if failed_count.zero?
        BulkDeleteOperation::STATUS_COMPLETED
      elsif deleted_count.positive?
        BulkDeleteOperation::STATUS_COMPLETED_WITH_ERRORS
      else
        BulkDeleteOperation::STATUS_FAILED
      end

    operation.update!(status: final_status, completed_at: Time.current)
    broadcast_status(operation)
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn("BulkDeleteContractsJob skipped: operation #{operation_id} not found")
  end

  private

  def update_progress(operation, processed_count:, deleted_count:, failed_count:)
    operation.update!(
      processed_count: processed_count,
      deleted_count: deleted_count,
      failed_count: failed_count
    )
    broadcast_status(operation)
  end

  def broadcast_status(operation)
    Turbo::StreamsChannel.broadcast_update_to(
      stream_name(operation.organization_id),
      target: "contracts_bulk_delete_status",
      partial: "contracts/bulk_delete_status",
      locals: { operation: operation }
    )
  end

  def broadcast_contract_removed(organization_id, contract)
    Turbo::StreamsChannel.broadcast_remove_to(
      stream_name(organization_id),
      target: dom_id(contract, :mobile_card)
    )
    Turbo::StreamsChannel.broadcast_remove_to(
      stream_name(organization_id),
      target: dom_id(contract, :desktop_row)
    )
  end

  def stream_name(organization_id)
    "contracts_#{organization_id}"
  end
end
