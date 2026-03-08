require "test_helper"

class ReviewFieldCatalogTest < ActiveSupport::TestCase
  test "covers every current alert family" do
    assert_equal Alert::ALERT_TYPES.sort, ReviewFieldCatalog.alert_families.keys.sort
  end

  test "catalog exposes canonical direct field metadata" do
    field = ReviewFieldCatalog.fetch("contract.end_date")

    assert_equal "alert_driving", field.classification
    assert_equal "alert_date", field.field_family
    assert field.direct?
    assert field.blocks_activation?
    assert_equal %w[expiry_warning notice_period_start], field.alert_families
  end

  test "catalog marks contextual lease fields as non-blocking" do
    field = ReviewFieldCatalog.fetch("lease_detail.percentage_rent_report_date")

    assert_equal "contextual", field.classification
    assert_equal "contextual_date", field.field_family
    assert field.lease_only?
    assert_not field.blocks_activation?
    assert field.applicable_to_contract_type?("lease")
    assert_not field.applicable_to_contract_type?("software")
  end

  test "derived fields expose explicit dependencies" do
    fallback = ReviewFieldCatalog.fetch("contract.next_renewal_date_fallback")
    notice_period = ReviewFieldCatalog.fetch("notice_period_start_date")

    assert fallback.derived?
    assert_equal %w[contract.auto_renews contract.end_date], fallback.dependencies

    assert notice_period.derived?
    assert_includes notice_period.dependencies, "contract.notice_period_days"
    assert_includes notice_period.dependencies, "contract.next_renewal_date_fallback"
  end

  test "alert family wiring includes direct governing and derived fields" do
    family = ReviewFieldCatalog.alert_family("notice_period_start")

    assert_equal %w[contract.notice_period_days contract.end_date contract.next_renewal_date], family.required_fields
    assert_equal %w[contract.auto_renews], family.governing_fields
    assert_equal %w[notice_period_start_date contract.next_renewal_date_fallback], family.derived_fields
  end

  test "lease-only alert families are guarded by applicability rules" do
    lease_families = ReviewFieldCatalog.applicable_alert_families(contract_type: "lease").map(&:key)
    software_families = ReviewFieldCatalog.applicable_alert_families(contract_type: "software").map(&:key)

    assert_includes lease_families, "cam_reconciliation"
    assert_includes lease_families, "milestone_reminder"
    assert_not_includes software_families, "cam_reconciliation"
    assert_not_includes software_families, "milestone_reminder"
    assert_includes software_families, "expiry_warning"
  end

  test "fields_for_alert returns the combined wiring set" do
    fields = ReviewFieldCatalog.fields_for_alert("milestone_reminder").map(&:key)

    assert_equal(
      %w[
        lease_milestone.due_date
        contract.contract_type
        lease_milestone.recurring
        lease_milestone.recurrence_interval
        recurring_milestone_next_occurrence_date
      ],
      fields
    )
  end

  test "status is represented as an app managed field" do
    field = ReviewFieldCatalog.fetch("contract.status")

    assert field.app_managed?
    assert_equal "app_managed", field.classification
    assert_equal "app_managed", field.field_family
    assert_not field.blocks_activation?
  end
end
