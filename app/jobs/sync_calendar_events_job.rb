# Syncs all calendar events for a single calendar connection.
# Enqueued when preferences change, connections are updated, or as periodic reconciliation.
class SyncCalendarEventsJob < ApplicationJob
  queue_as :default

  def perform(calendar_connection_id)
    connection = CalendarConnection.find(calendar_connection_id)
    CalendarSyncService.new(connection).sync!
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn("CalendarConnection #{calendar_connection_id} not found, skipping sync")
  end
end
