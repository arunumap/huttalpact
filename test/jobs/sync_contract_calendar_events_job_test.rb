require "test_helper"

class SyncContractCalendarEventsJobTest < ActiveJob::TestCase
  test "enqueues successfully" do
    contract = contracts(:commercial_lease)
    assert_enqueued_with(job: SyncContractCalendarEventsJob, args: [ contract.id ]) do
      SyncContractCalendarEventsJob.perform_later(contract.id)
    end
  end

  test "handles missing contract gracefully" do
    assert_nothing_raised do
      SyncContractCalendarEventsJob.perform_now(SecureRandom.uuid)
    end
  end
end
