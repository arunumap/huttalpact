require "test_helper"

class RentEscalationTest < ActiveSupport::TestCase
  setup do
    @escalation = rent_escalations(:year_one)
    @future = rent_escalations(:future_cpi)
  end

  test "valid rent escalation" do
    assert @escalation.valid?
  end

  test "belongs to contract" do
    assert_equal contracts(:commercial_lease), @escalation.contract
  end

  test "requires effective_date" do
    @escalation.effective_date = nil
    assert_not @escalation.valid?
  end

  test "requires escalation_type" do
    @escalation.escalation_type = nil
    assert_not @escalation.valid?
  end

  test "validates escalation_type inclusion" do
    @escalation.escalation_type = "invalid"
    assert_not @escalation.valid?
  end

  test "validates base_rent_monthly non-negative" do
    @escalation.base_rent_monthly = -1
    assert_not @escalation.valid?
  end

  test "future scope returns only future escalations" do
    contract = contracts(:commercial_lease)
    future = contract.rent_escalations.future
    future.each do |esc|
      assert esc.effective_date > Date.current
    end
  end

  test "past_or_current scope returns non-future escalations" do
    contract = contracts(:commercial_lease)
    past = contract.rent_escalations.past_or_current
    past.each do |esc|
      assert esc.effective_date <= Date.current
    end
  end

  test "current? identifies current escalation period" do
    # Year one started in 2025, so it should be current or past depending on when test runs
    # The most recent past_or_current is the current one
    contract = contracts(:commercial_lease)
    current_esc = contract.rent_escalations.past_or_current.last
    assert current_esc.current? if current_esc
  end

  test "escalation_type_label formats type" do
    @escalation.escalation_type = "fixed_percentage"
    assert_equal "Fixed Percentage", @escalation.escalation_type_label
  end

  test "escalation_description for fixed_percentage" do
    esc = rent_escalations(:year_two)
    desc = esc.escalation_description
    assert_includes desc, "3.0%"
  end

  test "escalation_description for cpi" do
    desc = @future.escalation_description
    assert_includes desc, "CPI"
  end

  test "ordered by effective_date ascending" do
    contract = contracts(:commercial_lease)
    dates = contract.rent_escalations.map(&:effective_date)
    assert_equal dates.sort, dates
  end
end
