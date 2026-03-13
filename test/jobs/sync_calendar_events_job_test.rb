require "test_helper"

class SyncCalendarEventsJobTest < ActiveJob::TestCase
  test "enqueues successfully" do
    connection = calendar_connections(:google_connection)
    assert_enqueued_with(job: SyncCalendarEventsJob, args: [ connection.id ]) do
      SyncCalendarEventsJob.perform_later(connection.id)
    end
  end

  test "handles missing connection gracefully" do
    assert_nothing_raised do
      SyncCalendarEventsJob.perform_now(SecureRandom.uuid)
    end
  end
end
