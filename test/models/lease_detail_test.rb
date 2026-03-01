require "test_helper"

class LeaseDetailTest < ActiveSupport::TestCase
  setup do
    @lease_detail = lease_details(:commercial_lease_detail)
  end

  test "valid lease detail" do
    assert @lease_detail.valid?
  end

  test "belongs to contract" do
    assert_equal contracts(:commercial_lease), @lease_detail.contract
  end

  test "validates lease_type inclusion" do
    @lease_detail.lease_type = "invalid"
    assert_not @lease_detail.valid?
  end

  test "allows blank lease_type" do
    @lease_detail.lease_type = nil
    assert @lease_detail.valid?
  end

  test "validates cam_cap_type inclusion" do
    @lease_detail.cam_cap_type = "invalid"
    assert_not @lease_detail.valid?
  end

  test "validates ti_disbursement_type inclusion" do
    @lease_detail.ti_disbursement_type = "invalid"
    assert_not @lease_detail.valid?
  end

  test "validates rentable_sqft positive" do
    @lease_detail.rentable_sqft = -100
    assert_not @lease_detail.valid?
  end

  test "validates security_deposit non-negative" do
    @lease_detail.security_deposit = -1
    assert_not @lease_detail.valid?
  end

  test "validates cam_reconciliation_month in 1..12" do
    @lease_detail.cam_reconciliation_month = 13
    assert_not @lease_detail.valid?

    @lease_detail.cam_reconciliation_month = 0
    assert_not @lease_detail.valid?
  end

  test "validates cam_cap_percentage range" do
    @lease_detail.cam_cap_percentage = 0
    assert_not @lease_detail.valid?

    @lease_detail.cam_cap_percentage = 101
    assert_not @lease_detail.valid?
  end

  test "nnn? returns true for nnn type" do
    assert @lease_detail.nnn?
    @lease_detail.lease_type = "gross"
    assert_not @lease_detail.nnn?
  end

  test "gross? returns true for gross type" do
    @lease_detail.lease_type = "gross"
    assert @lease_detail.gross?
  end

  test "has_cam? detects CAM data" do
    assert @lease_detail.has_cam?
    @lease_detail.cam_base_amount = nil
    @lease_detail.cam_base_year = nil
    @lease_detail.cam_cap_percentage = nil
    assert_not @lease_detail.has_cam?
  end

  test "has_ti? detects TI data" do
    assert @lease_detail.has_ti?
    @lease_detail.ti_allowance_psf = nil
    @lease_detail.ti_total_amount = nil
    assert_not @lease_detail.has_ti?
  end

  test "has_percentage_rent? detects percentage rent" do
    assert @lease_detail.has_percentage_rent?
    @lease_detail.percentage_rent_rate = nil
    @lease_detail.percentage_rent_breakpoint = nil
    assert_not @lease_detail.has_percentage_rent?
  end

  test "cam_reconciliation_date returns date for given year" do
    date = @lease_detail.cam_reconciliation_date(2026)
    assert_equal Date.new(2026, 3, 1), date
  end

  test "cam_reconciliation_date returns nil without month" do
    @lease_detail.cam_reconciliation_month = nil
    assert_nil @lease_detail.cam_reconciliation_date
  end

  test "next_cam_reconciliation_date returns future date" do
    date = @lease_detail.next_cam_reconciliation_date
    assert date > Date.current, "Next reconciliation date should be in the future"
  end

  test "ti_days_remaining calculates correctly" do
    remaining = @lease_detail.ti_days_remaining
    assert remaining > 0
    assert_equal (180.days.from_now.to_date - Date.current).to_i, remaining
  end

  test "ti_days_remaining returns nil without deadline" do
    @lease_detail.ti_deadline = nil
    assert_nil @lease_detail.ti_days_remaining
  end

  test "lease_type_label titleizes the type" do
    assert_equal "Nnn", @lease_detail.lease_type_label
  end

  test "cam_cap_type_label titleizes the type" do
    assert_equal "Cumulative", @lease_detail.cam_cap_type_label
  end

  test "ti_disbursement_type_label titleizes the type" do
    assert_equal "Draw Schedule", @lease_detail.ti_disbursement_type_label
  end
end
