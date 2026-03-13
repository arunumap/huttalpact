# Syncs calendar events for a single contract across all active calendar connections
# in the organization. Enqueued when contract dates, lease details, milestones, etc. change.
class SyncContractCalendarEventsJob < ApplicationJob
  queue_as :default

  def perform(contract_id)
    contract = Contract.find(contract_id)
    organization = contract.organization

    organization.calendar_connections.active.includes(:calendar_preference).find_each do |connection|
      next unless connection.calendar_preference&.sync_enabled?

      CalendarSyncService.new(connection).sync_contract!(contract)
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn("Contract #{contract_id} not found, skipping calendar sync")
  end
end
