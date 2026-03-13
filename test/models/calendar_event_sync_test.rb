require "test_helper"

class CalendarEventSyncTest < ActiveSupport::TestCase
  setup do
    @connection = calendar_connections(:google_connection)
    @contract = contracts(:commercial_lease)
    @sync = CalendarEventSync.create!(
      calendar_connection: @connection,
      organization: organizations(:one),
      source: @contract,
      event_category: "expiry_warning",
      remote_event_id: "google_event_123",
      remote_calendar_id: "primary",
      payload_fingerprint: "abc123",
      sync_status: "synced",
      last_synced_at: Time.current
    )
  end

  test "valid sync record" do
    assert @sync.valid?
  end

  test "requires event_category" do
    @sync.event_category = nil
    assert_not @sync.valid?
  end

  test "requires valid event_category" do
    @sync.event_category = "invalid"
    assert_not @sync.valid?
  end

  test "enforces uniqueness per connection-source-category" do
    duplicate = @sync.dup
    duplicate.id = nil
    assert_not duplicate.valid?
  end

  test "needs_update? compares fingerprints" do
    assert_not @sync.needs_update?("abc123")
    assert @sync.needs_update?("different_fingerprint")
  end

  test "mark_synced!" do
    @sync.update!(sync_status: "pending")
    @sync.mark_synced!(remote_event_id: "new_id", fingerprint: "new_fp")
    assert_equal "synced", @sync.sync_status
    assert_equal "new_id", @sync.remote_event_id
    assert_equal "new_fp", @sync.payload_fingerprint
    assert_nil @sync.last_error
  end

  test "mark_failed!" do
    @sync.mark_failed!("API timeout")
    assert_equal "failed", @sync.sync_status
    assert_equal "API timeout", @sync.last_error
    assert_equal 1, @sync.retry_count
  end

  test "mark_deleted!" do
    @sync.mark_deleted!
    assert_equal "deleted", @sync.sync_status
  end

  test "retriable?" do
    @sync.update!(sync_status: "failed", retry_count: 0)
    assert @sync.retriable?

    @sync.update!(retry_count: CalendarEventSync::MAX_RETRIES)
    assert_not @sync.retriable?
  end

  test "scopes" do
    assert CalendarEventSync.synced.include?(@sync)

    @sync.update!(sync_status: "failed")
    assert CalendarEventSync.failed.include?(@sync)

    @sync.update!(sync_status: "pending")
    assert CalendarEventSync.pending.include?(@sync)
  end
end
