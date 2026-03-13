require "test_helper"

class CalendarSyncServiceTest < ActiveSupport::TestCase
  class FakeAdapter
    attr_reader :created_calls, :updated_calls, :deleted_calls

    def initialize(fail_create: false)
      @fail_create = fail_create
      @created_calls = []
      @updated_calls = []
      @deleted_calls = []
    end

    def create_event(calendar_id, candidate, app_host:)
      raise "provider create failed" if @fail_create

      @created_calls << [ calendar_id, candidate.source_type, candidate.source_id, candidate.event_category, app_host ]
      "remote-#{@created_calls.size}"
    end

    def update_event(calendar_id, remote_event_id, candidate, app_host:)
      @updated_calls << [ calendar_id, remote_event_id, candidate.fingerprint, app_host ]
      remote_event_id
    end

    def delete_event(calendar_id, remote_event_id)
      @deleted_calls << [ calendar_id, remote_event_id ]
    end
  end

  setup do
    @connection = calendar_connections(:google_connection)
    @organization = organizations(:one)
    @contract = contracts(:commercial_lease)
    @service = CalendarSyncService.new(@connection)
  end

  test "sync! creates sync record when candidate is new" do
    candidate = build_candidate
    adapter = FakeAdapter.new

    with_stubbed_projector([ candidate ]) do
      with_stubbed_adapter(adapter) { @service.sync! }
    end

    sync = CalendarEventSync.find_by!(
      calendar_connection: @connection,
      source_type: "Contract",
      source_id: @contract.id,
      event_category: "expiry_warning"
    )
    assert_equal "synced", sync.sync_status
    assert_equal "remote-1", sync.remote_event_id
    assert_equal candidate.fingerprint, sync.payload_fingerprint
    assert_equal 1, adapter.created_calls.size
  end

  test "sync! updates existing sync when fingerprint changes" do
    existing = CalendarEventSync.create!(
      calendar_connection: @connection,
      organization: @organization,
      source: @contract,
      event_category: "expiry_warning",
      remote_event_id: "remote-existing",
      remote_calendar_id: "primary",
      payload_fingerprint: "old-fingerprint",
      sync_status: "synced"
    )
    candidate = build_candidate(description: "updated description")
    adapter = FakeAdapter.new

    with_stubbed_projector([ candidate ]) do
      with_stubbed_adapter(adapter) { @service.sync! }
    end

    assert_equal 1, adapter.updated_calls.size
    assert_equal candidate.fingerprint, existing.reload.payload_fingerprint
  end

  test "sync! deletes stale syncs that are no longer projected" do
    stale = CalendarEventSync.create!(
      calendar_connection: @connection,
      organization: @organization,
      source: @contract,
      event_category: "renewal_upcoming",
      remote_event_id: "remote-stale",
      remote_calendar_id: "primary",
      payload_fingerprint: "stale-fingerprint",
      sync_status: "synced"
    )
    adapter = FakeAdapter.new

    with_stubbed_projector([]) do
      with_stubbed_adapter(adapter) { @service.sync! }
    end

    assert_equal [ [ "primary", "remote-stale" ] ], adapter.deleted_calls
    assert_equal "deleted", stale.reload.sync_status
  end

  test "sync! marks record as failed when provider create fails" do
    candidate = build_candidate
    adapter = FakeAdapter.new(fail_create: true)

    with_stubbed_projector([ candidate ]) do
      with_stubbed_adapter(adapter) { @service.sync! }
    end

    failed = CalendarEventSync.find_by!(
      calendar_connection: @connection,
      source_type: "Contract",
      source_id: @contract.id,
      event_category: "expiry_warning"
    )
    assert_equal "failed", failed.sync_status
    assert_equal 1, failed.retry_count
    assert_includes failed.last_error, "provider create failed"
  end

  test "sync! creates remote event for pending sync with no remote event id" do
    pending = CalendarEventSync.create!(
      calendar_connection: @connection,
      organization: @organization,
      source: @contract,
      event_category: "expiry_warning",
      remote_calendar_id: "primary",
      sync_status: "pending"
    )
    candidate = build_candidate
    adapter = FakeAdapter.new

    with_stubbed_projector([ candidate ]) do
      with_stubbed_adapter(adapter) { @service.sync! }
    end

    assert_equal 1, adapter.created_calls.size
    assert_equal "synced", pending.reload.sync_status
    assert_equal "remote-1", pending.remote_event_id
  end

  test "sync_contract! only syncs candidates related to the provided contract" do
    other_contract = contracts(:hvac_maintenance)
    candidate_for_target = build_candidate(source_id: @contract.id)
    candidate_for_other = build_candidate(source_id: other_contract.id)
    adapter = FakeAdapter.new

    with_stubbed_projector([ candidate_for_target, candidate_for_other ]) do
      with_stubbed_adapter(adapter) { @service.sync_contract!(@contract) }
    end

    assert CalendarEventSync.exists?(
      calendar_connection: @connection,
      source_type: "Contract",
      source_id: @contract.id,
      event_category: "expiry_warning"
    )
    assert_not CalendarEventSync.exists?(
      calendar_connection: @connection,
      source_type: "Contract",
      source_id: other_contract.id,
      event_category: "expiry_warning"
    )
  end

  private

  def build_candidate(source_id: @contract.id, description: "Contract expiration date")
    CalendarEventProjector::CalendarCandidate.new(
      source_type: "Contract",
      source_id: source_id,
      event_category: "expiry_warning",
      title: "Lease Expires",
      date: 30.days.from_now.to_date,
      description: description,
      deep_link_path: "/contracts/#{source_id}",
      reminder_days: 30
    )
  end

  def with_stubbed_projector(candidates)
    projector = Object.new
    projector.define_singleton_method(:project) { |categories:| candidates }
    CalendarEventProjector.stub(:new, projector) { yield }
  end

  def with_stubbed_adapter(adapter)
    CalendarProviders::GoogleAdapter.stub(:new, adapter) { yield }
  end
end
