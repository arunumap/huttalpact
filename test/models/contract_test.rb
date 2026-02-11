require "test_helper"

class ContractTest < ActiveSupport::TestCase
  setup do
    @contract = contracts(:hvac_maintenance)
  end

  test "valid contract" do
    assert @contract.valid?
  end

  test "requires title" do
    @contract.title = nil
    assert_not @contract.valid?
    assert_includes @contract.errors[:title], "can't be blank"
  end

  test "validates status inclusion" do
    @contract.status = "invalid_status"
    assert_not @contract.valid?
  end

  test "validates contract_type inclusion" do
    @contract.contract_type = "invalid_type"
    assert_not @contract.valid?
  end

  test "allows blank contract_type" do
    @contract.contract_type = nil
    assert @contract.valid?
  end

  test "validates monthly_value is non-negative" do
    @contract.monthly_value = -100
    assert_not @contract.valid?
  end

  test "active scope" do
    active = Contract.active
    assert_includes active, contracts(:hvac_maintenance)
    assert_not_includes active, contracts(:expired_insurance)
  end

  test "expiring_soon scope" do
    expiring = Contract.expiring_soon
    assert_includes expiring, contracts(:landscaping)
    assert_not_includes expiring, contracts(:hvac_maintenance)
  end

  test "expired scope" do
    expired = Contract.expired
    assert_includes expired, contracts(:expired_insurance)
    assert_not_includes expired, contracts(:hvac_maintenance)
  end

  test "by_type scope" do
    maintenance = Contract.by_type("maintenance")
    assert_includes maintenance, contracts(:hvac_maintenance)
    assert_not_includes maintenance, contracts(:landscaping)
  end

  test "search scope finds by title" do
    results = Contract.search("HVAC")
    assert_includes results, contracts(:hvac_maintenance)
    assert_not_includes results, contracts(:landscaping)
  end

  test "search scope finds by vendor" do
    results = Contract.search("Green Thumb")
    assert_includes results, contracts(:landscaping)
    assert_not_includes results, contracts(:hvac_maintenance)
  end

  test "search scope is case-insensitive" do
    results = Contract.search("hvac")
    assert_includes results, contracts(:hvac_maintenance)
  end

  test "status_label returns formatted status" do
    assert_equal "Active", contracts(:hvac_maintenance).status_label
    assert_equal "Expiring Soon", contracts(:landscaping).status_label
  end

  test "contract_type_label returns formatted type" do
    assert_equal "Maintenance", contracts(:hvac_maintenance).contract_type_label
    assert_equal "Service Agreement", contracts(:landscaping).contract_type_label
  end

  test "days_until_expiry returns correct days" do
    contract = Contract.new(end_date: 30.days.from_now.to_date)
    assert_equal 30, contract.days_until_expiry
  end

  test "days_until_expiry returns nil without end_date" do
    contract = Contract.new
    assert_nil contract.days_until_expiry
  end

  test "days_until_renewal returns correct days" do
    contract = Contract.new(next_renewal_date: 60.days.from_now.to_date)
    assert_equal 60, contract.days_until_renewal
  end

  test "belongs to organization" do
    assert_equal organizations(:one), @contract.organization
  end

  test "belongs to uploaded_by user" do
    assert_equal users(:one), @contract.uploaded_by
  end

  # Direction tests
  test "validates direction inclusion" do
    @contract.direction = "invalid"
    assert_not @contract.valid?
    assert_includes @contract.errors[:direction], "is not included in the list"
  end

  test "direction defaults to outbound" do
    contract = Contract.new(title: "Test", status: "active", organization: organizations(:one))
    assert_equal "outbound", contract.direction
  end

  test "inbound scope returns only inbound contracts" do
    inbound = Contract.inbound
    assert inbound.all? { |c| c.direction == "inbound" }
    assert_includes inbound, contracts(:landscaping)
  end

  test "outbound scope returns only outbound contracts" do
    outbound = Contract.outbound
    assert outbound.all? { |c| c.direction == "outbound" }
    assert_includes outbound, contracts(:hvac_maintenance)
  end

  test "by_direction scope filters correctly" do
    assert_includes Contract.by_direction("inbound"), contracts(:landscaping)
    assert_not_includes Contract.by_direction("inbound"), contracts(:hvac_maintenance)
  end

  test "direction_label returns Revenue for inbound" do
    @contract.direction = "inbound"
    assert_equal "Revenue", @contract.direction_label
  end

  test "direction_label returns Expense for outbound" do
    @contract.direction = "outbound"
    assert_equal "Expense", @contract.direction_label
  end

  test "inbound? returns true for inbound contracts" do
    @contract.direction = "inbound"
    assert @contract.inbound?
    assert_not @contract.outbound?
  end

  test "outbound? returns true for outbound contracts" do
    @contract.direction = "outbound"
    assert @contract.outbound?
    assert_not @contract.inbound?
  end

  # Archived status tests
  test "archived is a valid status" do
    @contract.status = "archived"
    assert @contract.valid?
  end

  test "archived scope returns only archived contracts" do
    @contract.update!(status: "archived")
    assert_includes Contract.archived, @contract
  end

  test "not_archived scope excludes archived contracts" do
    @contract.update!(status: "archived")
    assert_not_includes Contract.not_archived, @contract
    assert_includes Contract.not_archived, contracts(:landscaping)
  end

  test "expiring_within excludes archived contracts" do
    @contract.update!(status: "archived", end_date: 10.days.from_now)
    assert_not_includes Contract.expiring_within(30), @contract
  end

  test "model validation prevents creation when at contract limit" do
    org = organizations(:one)
    # Set plan to free (limit 10) and fake enough non-archived contracts
    org.update!(plan: "free")
    # Archive all existing, then create exactly 10
    org.contracts.update_all(status: "archived")
    10.times do |i|
      Contract.create!(title: "Filler #{i}", status: "active", organization: org)
    end

    contract = Contract.new(title: "Over Limit", status: "active", organization: org)
    assert_not contract.valid?
    assert_includes contract.errors[:base].join, "Contract limit reached"
  end

  test "model validation allows creation when under limit" do
    org = organizations(:one)
    org.update!(plan: "free")
    # Org has < 10 non-archived contracts from fixtures
    contract = Contract.new(title: "Under Limit", status: "active", organization: org)
    assert contract.valid?
  end

  test "model validation skips for pro plan" do
    org = organizations(:one)
    org.update!(plan: "pro")
    contract = Contract.new(title: "Pro Contract", status: "active", organization: org)
    assert contract.valid?
  end

  # Date ordering validation tests
  test "rejects end_date before start_date" do
    @contract.start_date = Date.new(2026, 6, 1)
    @contract.end_date = Date.new(2026, 1, 1)
    assert_not @contract.valid?
    assert_includes @contract.errors[:end_date], "must be after the start date"
  end

  test "accepts end_date after start_date" do
    @contract.start_date = Date.new(2026, 1, 1)
    @contract.end_date = Date.new(2026, 12, 31)
    assert @contract.valid?
  end

  test "allows missing start_date with end_date present" do
    @contract.start_date = nil
    @contract.end_date = Date.new(2026, 12, 31)
    assert @contract.valid?
  end

  test "allows missing end_date with start_date present" do
    @contract.start_date = Date.new(2026, 1, 1)
    @contract.end_date = nil
    assert @contract.valid?
  end

  test "rejects next_renewal_date before start_date" do
    @contract.start_date = Date.new(2026, 6, 1)
    @contract.next_renewal_date = Date.new(2025, 1, 1)
    assert_not @contract.valid?
    assert_includes @contract.errors[:next_renewal_date], "must be on or after the start date"
  end

  test "accepts next_renewal_date equal to start_date" do
    @contract.start_date = Date.new(2026, 6, 1)
    @contract.next_renewal_date = Date.new(2026, 6, 1)
    assert @contract.valid?
  end

  # String length validation tests
  test "rejects title longer than 255 characters" do
    @contract.title = "a" * 256
    assert_not @contract.valid?
    assert_includes @contract.errors[:title], "is too long (maximum is 255 characters)"
  end

  test "rejects vendor_name longer than 255 characters" do
    @contract.vendor_name = "a" * 256
    assert_not @contract.valid?
    assert_includes @contract.errors[:vendor_name], "is too long (maximum is 255 characters)"
  end

  # Vendor name normalization
  test "normalizes vendor_name by stripping and squeezing whitespace" do
    @contract.vendor_name = "  Cool  Air   Services  "
    assert_equal "Cool Air Services", @contract.vendor_name
  end

  # Contract limit bypass: reactivation from archived
  test "prevents reactivation from archived when at contract limit" do
    org = organizations(:one)
    org.update!(plan: "free")
    org.contracts.update_all(status: "archived")
    10.times do |i|
      Contract.create!(title: "Filler #{i}", status: "active", organization: org)
    end

    archived_contract = org.contracts.archived.first
    archived_contract.status = "active"
    assert_not archived_contract.valid?
    assert_includes archived_contract.errors[:base].join, "Contract limit reached"
  end

  test "allows reactivation from archived when under limit" do
    org = organizations(:one)
    org.update!(plan: "free")
    org.contracts.update_all(status: "archived")
    Contract.create!(title: "Only Active One", status: "active", organization: org)

    archived_contract = org.contracts.archived.first
    archived_contract.status = "active"
    assert archived_contract.valid?
  end

  test "allows status change between active statuses without limit check" do
    @contract.status = "expiring_soon"
    assert @contract.valid?
  end

  # total_value validation
  test "validates total_value is non-negative" do
    @contract.total_value = -500
    assert_not @contract.valid?
    assert_includes @contract.errors[:total_value], "must be greater than or equal to 0"
  end

  test "allows nil total_value" do
    @contract.total_value = nil
    assert @contract.valid?
  end

  # notice_period_days validation
  test "validates notice_period_days is non-negative" do
    @contract.notice_period_days = -5
    assert_not @contract.valid?
    assert_includes @contract.errors[:notice_period_days], "must be greater than or equal to 0"
  end

  test "validates notice_period_days is an integer" do
    @contract.notice_period_days = 3.5
    assert_not @contract.valid?
    assert_includes @contract.errors[:notice_period_days], "must be an integer"
  end

  test "allows nil notice_period_days" do
    @contract.notice_period_days = nil
    assert @contract.valid?
  end

  # renewal_term validation
  test "validates renewal_term inclusion" do
    @contract.renewal_term = "invalid_term"
    assert_not @contract.valid?
    assert_includes @contract.errors[:renewal_term], "is not included in the list"
  end

  test "allows blank renewal_term" do
    @contract.renewal_term = nil
    assert @contract.valid?
  end

  test "accepts valid renewal_terms" do
    %w[month-to-month annual 2-year custom].each do |term|
      @contract.renewal_term = term
      assert @contract.valid?, "Expected '#{term}' to be valid"
    end
  end

  # extraction_status validation
  test "validates extraction_status inclusion" do
    @contract.extraction_status = "bogus"
    assert_not @contract.valid?
    assert_includes @contract.errors[:extraction_status], "is not included in the list"
  end

  test "accepts valid extraction_statuses" do
    %w[pending processing completed failed].each do |es|
      @contract.extraction_status = es
      assert @contract.valid?, "Expected '#{es}' to be valid"
    end
  end

  # notes length validation
  test "rejects notes longer than 10000 characters" do
    @contract.notes = "a" * 10_001
    assert_not @contract.valid?
    assert_includes @contract.errors[:notes], "is too long (maximum is 10000 characters)"
  end

  test "allows notes at exactly 10000 characters" do
    @contract.notes = "a" * 10_000
    assert @contract.valid?
  end

  # renewal_within scope
  test "renewal_within scope returns contracts with renewal in range" do
    @contract.update!(next_renewal_date: 15.days.from_now.to_date)
    assert_includes Contract.renewal_within(30), @contract
    assert_not_includes Contract.renewal_within(10), @contract
  end

  # by_status scope
  test "by_status scope filters correctly" do
    assert_includes Contract.by_status("active"), contracts(:hvac_maintenance)
    assert_not_includes Contract.by_status("active"), contracts(:expired_insurance)
  end

  # days_until_renewal nil case
  test "days_until_renewal returns nil without next_renewal_date" do
    contract = Contract.new
    assert_nil contract.days_until_renewal
  end

  # search with SQL wildcard characters
  test "search scope escapes SQL wildcard characters" do
    contract = Contract.create!(
      title: "100% Coverage Plan",
      status: "active",
      organization: organizations(:one)
    )
    results = Contract.search("100%")
    assert_includes results, contract
    # Should not match contracts that merely have "100" in them
    # because % is escaped and not treated as a wildcard
  end

  test "search scope escapes underscore wildcard" do
    contract = Contract.create!(
      title: "Plan_v2 Agreement",
      status: "active",
      organization: organizations(:one)
    )
    results = Contract.search("Plan_v2")
    assert_includes results, contract
  end

  # dependent: :destroy cascading
  test "destroying contract cascades to contract_documents and key_clauses" do
    contract = Contract.create!(
      title: "Cascade Test",
      status: "active",
      organization: organizations(:one)
    )
    clause = contract.key_clauses.create!(clause_type: "termination", content: "30 days notice")
    alert = contract.alerts.create!(
      organization: organizations(:one),
      alert_type: "renewal_upcoming",
      trigger_date: 30.days.from_now,
      status: "pending",
      message: "Test alert"
    )

    contract.destroy!

    assert_not KeyClause.exists?(clause.id), "Key clause should be destroyed"
    assert_not Alert.exists?(alert.id), "Alert should be destroyed"
  end

  test "destroying contract nullifies audit_logs" do
    contract = Contract.create!(
      title: "Nullify Test",
      status: "active",
      organization: organizations(:one)
    )
    log = AuditLog.create!(
      organization: organizations(:one),
      contract: contract,
      action: "created",
      details: "Test"
    )

    contract.destroy!

    assert AuditLog.exists?(log.id), "Audit log should still exist"
    assert_nil log.reload.contract_id, "Audit log contract_id should be nullified"
  end

  # Draft status tests
  test "draft status is valid" do
    @contract.status = "draft"
    assert @contract.valid?
  end

  test "draft? returns true for draft contracts" do
    @contract.status = "draft"
    assert @contract.draft?
  end

  test "draft? returns false for non-draft contracts" do
    assert_not @contract.draft?
  end

  test "draft contracts do not require title" do
    contract = Contract.new(
      status: "draft",
      organization: organizations(:one)
    )
    contract.title = nil
    assert contract.valid?, "Draft should be valid without title: #{contract.errors.full_messages}"
  end

  test "non-draft contracts require title" do
    contract = Contract.new(
      status: "active",
      organization: organizations(:one)
    )
    contract.title = nil
    assert_not contract.valid?
    assert_includes contract.errors[:title], "can't be blank"
  end

  test "draft scope returns only draft contracts" do
    draft = Contract.create!(title: "Draft", status: "draft", organization: organizations(:one))
    assert_includes Contract.draft, draft
    assert_not_includes Contract.draft, @contract
  end

  test "not_draft scope excludes draft contracts" do
    draft = Contract.create!(title: "Draft", status: "draft", organization: organizations(:one))
    assert_not_includes Contract.not_draft, draft
    assert_includes Contract.not_draft, @contract
  end

  test "not_archived scope excludes both archived and draft contracts" do
    draft = Contract.create!(title: "Draft", status: "draft", organization: organizations(:one))
    archived = contracts(:hvac_maintenance).dup
    archived.update!(status: "archived", title: "Archived Copy")

    assert_not_includes Contract.not_archived, draft
    assert_not_includes Contract.not_archived, archived
  end

  test "draft contracts skip contract limit validation" do
    org = organizations(:one)
    org.update!(plan: "free")
    org.contracts.update_all(status: "archived")
    10.times { |i| Contract.create!(title: "Filler #{i}", status: "active", organization: org) }
    assert org.reload.at_contract_limit?

    draft = Contract.new(title: "Draft", status: "draft", organization: org)
    assert draft.valid?, "Draft should bypass contract limit: #{draft.errors.full_messages}"
  end

  test "STATUSES includes draft" do
    assert_includes Contract::STATUSES, "draft"
  end

  test "ACTIVE_STATUSES excludes draft" do
    assert_not_includes Contract::ACTIVE_STATUSES, "draft"
  end
end
