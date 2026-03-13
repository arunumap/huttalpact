require "test_helper"

class CalendarMaintenanceJobTest < ActiveJob::TestCase
  test "runs without error" do
    assert_nothing_raised do
      CalendarMaintenanceJob.perform_now
    end
  end

  test "prunes old deleted syncs" do
    connection = calendar_connections(:google_connection)
    contract = contracts(:commercial_lease)

    old_sync = CalendarEventSync.create!(
      calendar_connection: connection,
      organization: organizations(:one),
      source: contract,
      event_category: "expiry_warning",
      remote_calendar_id: "primary",
      sync_status: "deleted",
      updated_at: 31.days.ago
    )

    CalendarMaintenanceJob.perform_now
    assert_not CalendarEventSync.exists?(old_sync.id)
  end

  test "enqueues one retry sync job per active connection" do
    connection = calendar_connections(:google_connection)
    contract = contracts(:commercial_lease)

    CalendarEventSync.create!(
      calendar_connection: connection,
      organization: organizations(:one),
      source: contract,
      event_category: "expiry_warning",
      remote_calendar_id: "primary",
      sync_status: "failed",
      retry_count: 0
    )

    CalendarEventSync.create!(
      calendar_connection: connection,
      organization: organizations(:one),
      source: contract,
      event_category: "renewal_upcoming",
      remote_calendar_id: "primary",
      sync_status: "failed",
      retry_count: 0
    )

    assert_enqueued_jobs 1, only: SyncCalendarEventsJob do
      CalendarMaintenanceJob.perform_now
    end
  end
end
