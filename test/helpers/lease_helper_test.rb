require "test_helper"

class LeaseHelperTest < ActionView::TestCase
  include ApplicationHelper

  test "lease_type_badge returns badge for nnn" do
    badge = lease_type_badge("nnn")
    assert_match(/NNN/, badge)
    assert_match(/Triple Net/, badge)
    assert_match(/rounded-full/, badge)
  end

  test "lease_type_badge returns badge for gross" do
    badge = lease_type_badge("gross")
    assert_match(/Gross/, badge)
  end

  test "lease_type_badge returns badge for modified_gross" do
    badge = lease_type_badge("modified_gross")
    assert_match(/Modified Gross/, badge)
  end

  test "lease_type_badge handles unknown type" do
    badge = lease_type_badge("unknown")
    assert_match(/Unknown/, badge)
  end

  test "option_type_badge returns badge for renewal" do
    badge = option_type_badge("renewal")
    assert_match(/Renewal/, badge)
  end

  test "option_type_badge returns readable ROFR" do
    badge = option_type_badge("rofr")
    assert_match(/Right of First Refusal/, badge)
  end

  test "option_type_badge returns readable ROFO" do
    badge = option_type_badge("rofo")
    assert_match(/Right of First Offer/, badge)
  end

  test "escalation_type_badge returns badge for fixed_percentage" do
    badge = escalation_type_badge("fixed_percentage")
    assert_match(/Fixed %/, badge)
  end

  test "escalation_type_badge returns badge for cpi" do
    badge = escalation_type_badge("cpi")
    assert_match(/CPI/, badge)
  end

  test "escalation_type_badge returns badge for fmv_reset" do
    badge = escalation_type_badge("fmv_reset")
    assert_match(/FMV Reset/, badge)
  end

  test "milestone_type_badge returns badge for cam_reconciliation" do
    badge = milestone_type_badge("cam_reconciliation")
    assert_match(/Cam Reconciliation/, badge)
  end

  test "milestone_type_badge returns badge for insurance_renewal" do
    badge = milestone_type_badge("insurance_renewal")
    assert_match(/Insurance Renewal/, badge)
  end

  test "clause_type_badge handles new lease clause types" do
    %w[security_deposit cam_provision maintenance_responsibility subletting_assignment
       exclusivity co_tenancy parking signage hazmat ada_compliance subordination
       use_restriction tenant_improvement].each do |type|
      badge = clause_type_badge(type)
      assert_match(/rounded-full/, badge, "#{type} should produce a badge")
    end
  end

  test "alert_type_badge handles new lease alert types" do
    %w[option_exercise_deadline rent_escalation_date cam_reconciliation
       ti_deadline milestone_reminder].each do |type|
      badge = alert_type_badge(type)
      assert_match(/rounded-full/, badge, "#{type} should produce a badge")
    end
  end
end
