# Periodic job that refreshes expiring OAuth tokens and retries failed syncs.
# Runs on a recurring schedule via config/recurring.yml.
class CalendarMaintenanceJob < ApplicationJob
  queue_as :default

  def perform
    refresh_expiring_tokens
    retry_failed_syncs
    prune_deleted_syncs
  end

  private

  def refresh_expiring_tokens
    CalendarConnection.needs_token_refresh.find_each do |connection|
      adapter = build_adapter(connection)
      adapter.refresh_token!
    rescue => e
      connection.mark_error!("Token refresh failed: #{e.message}")
      Rails.logger.error("Token refresh failed for connection #{connection.id}: #{e.message}")
      Sentry.capture_exception(e) if Sentry.initialized?
    end
  end

  def retry_failed_syncs
    CalendarEventSync.retriable.includes(:calendar_connection).find_each do |sync_record|
      next unless sync_record.calendar_connection.active?

      SyncCalendarEventsJob.perform_later(sync_record.calendar_connection_id)
    end
  end

  def prune_deleted_syncs
    CalendarEventSync.deleted.where("updated_at < ?", 30.days.ago).delete_all
  end

  def build_adapter(connection)
    case connection.provider
    when "google" then CalendarProviders::GoogleAdapter.new(connection)
    when "microsoft" then CalendarProviders::MicrosoftAdapter.new(connection)
    end
  end
end
