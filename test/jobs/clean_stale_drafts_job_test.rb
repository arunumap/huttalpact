require "test_helper"

class CleanStaleDraftsJobTest < ActiveJob::TestCase
  setup do
    @org = organizations(:one)
  end

  test "deletes drafts older than 7 days" do
    old_draft = Contract.create!(
      title: "Old Draft",
      status: "draft",
      organization: @org
    )
    old_draft.update_column(:updated_at, 8.days.ago)

    assert_difference "Contract.count", -1 do
      CleanStaleDraftsJob.perform_now
    end

    assert_nil Contract.find_by(id: old_draft.id)
  end

  test "keeps recent drafts" do
    recent_draft = Contract.create!(
      title: "Recent Draft",
      status: "draft",
      organization: @org
    )

    assert_no_difference "Contract.count" do
      CleanStaleDraftsJob.perform_now
    end

    assert Contract.exists?(id: recent_draft.id)
  end

  test "does not delete non-draft contracts" do
    active_contract = contracts(:hvac_maintenance)
    active_contract.update_column(:updated_at, 30.days.ago)

    assert_no_difference "Contract.count" do
      CleanStaleDraftsJob.perform_now
    end
  end

  test "deletes multiple stale drafts" do
    3.times do |i|
      draft = Contract.create!(
        title: "Stale #{i}",
        status: "draft",
        organization: @org
      )
      draft.update_column(:updated_at, 10.days.ago)
    end

    assert_difference "Contract.count", -3 do
      CleanStaleDraftsJob.perform_now
    end
  end
end
