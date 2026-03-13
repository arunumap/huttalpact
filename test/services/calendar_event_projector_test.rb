require "test_helper"

class CalendarEventProjectorTest < ActiveSupport::TestCase
  setup do
    @organization = organizations(:one)
    @user = users(:one)
    @contract = contracts(:commercial_lease)
  end

  test "projects expiry_warning for contract with future end_date" do
    projector = CalendarEventProjector.new(organization: @organization, user: @user)
    candidates = projector.project(categories: [ "expiry_warning" ])

    expiry_candidates = candidates.select { |c| c.event_category == "expiry_warning" }
    contract_candidate = expiry_candidates.find { |c| c.source_id == @contract.id }

    if @contract.end_date.present? && @contract.end_date > Date.current
      assert_not_nil contract_candidate, "Should project expiry_warning for contract with future end_date"
      assert_includes contract_candidate.title, "Expires"
      assert_equal @contract.end_date, contract_candidate.date
      assert_equal "Contract", contract_candidate.source_type
    end
  end

  test "projects renewal_upcoming for contract with future renewal date" do
    projector = CalendarEventProjector.new(organization: @organization, user: @user)
    candidates = projector.project(categories: [ "renewal_upcoming" ])

    renewal_candidates = candidates.select { |c| c.event_category == "renewal_upcoming" }
    contract_candidate = renewal_candidates.find { |c| c.source_id == @contract.id }

    if @contract.next_renewal_date.present? && @contract.next_renewal_date > Date.current
      assert_not_nil contract_candidate, "Should project renewal_upcoming"
      assert_includes contract_candidate.title, "Renewal"
    end
  end

  test "projects milestone_reminder for lease milestones" do
    projector = CalendarEventProjector.new(organization: @organization, user: @user)
    candidates = projector.project(categories: [ "milestone_reminder" ])

    milestone_candidates = candidates.select { |c| c.event_category == "milestone_reminder" }
    assert milestone_candidates.any?, "Should project milestone reminders for lease milestones"
  end

  test "respects category filtering" do
    projector = CalendarEventProjector.new(organization: @organization, user: @user)

    all_candidates = projector.project
    filtered_candidates = projector.project(categories: [ "expiry_warning" ])

    assert filtered_candidates.all? { |c| c.event_category == "expiry_warning" }
    assert all_candidates.size >= filtered_candidates.size
  end

  test "skips expired and cancelled contracts" do
    projector = CalendarEventProjector.new(organization: @organization, user: @user)
    candidates = projector.project

    source_ids = candidates.map(&:source_id)
    Contract.where(status: %w[expired cancelled]).pluck(:id).each do |id|
      assert_not_includes source_ids, id, "Should not include expired/cancelled contracts"
    end
  end

  test "candidate fingerprint is deterministic" do
    projector = CalendarEventProjector.new(organization: @organization, user: @user)
    candidates1 = projector.project(categories: [ "expiry_warning" ])

    projector2 = CalendarEventProjector.new(organization: @organization, user: @user)
    candidates2 = projector2.project(categories: [ "expiry_warning" ])

    if candidates1.any?
      assert_equal candidates1.first.fingerprint, candidates2.first.fingerprint
    end
  end

  test "includes deep_link_path in candidates" do
    projector = CalendarEventProjector.new(organization: @organization, user: @user)
    candidates = projector.project

    candidates.each do |candidate|
      assert candidate.deep_link_path.present?, "Candidate should have a deep_link_path"
      assert candidate.deep_link_path.start_with?("/contracts/"), "Deep link should point to contract"
    end
  end

  test "includes reminder_days from alert preferences" do
    projector = CalendarEventProjector.new(organization: @organization, user: @user)
    candidates = projector.project(categories: [ "expiry_warning" ])

    pref = AlertPreference.for(@user, @organization)
    candidates.each do |candidate|
      assert_equal pref.days_before_expiry, candidate.reminder_days
    end
  end
end
