class ContractStatusUpdaterJob < ApplicationJob
  queue_as :default

  def perform
    # Mark expired: active contracts whose end_date has passed
    expired_contract_ids = Contract.where(status: "active")
                                   .where(end_date: ..Date.current)
                                   .pluck(:id)

    if expired_contract_ids.any?
      Contract.where(id: expired_contract_ids).update_all(status: "expired", updated_at: Time.current)

      # Cancel pending/snoozed alerts for expired contracts
      Alert.where(contract_id: expired_contract_ids, status: %w[pending snoozed])
           .update_all(status: "cancelled", updated_at: Time.current)
    end

    # Mark expiring_soon: active contracts ending within 30 days
    expiring_count = Contract.where(status: "active")
                             .where(end_date: (Date.current + 1)..(Date.current + 30))
                             .update_all(status: "expiring_soon", updated_at: Time.current)

    Rails.logger.info("ContractStatusUpdater: #{expired_contract_ids.size} expired, #{expiring_count} marked expiring_soon")
  end
end
