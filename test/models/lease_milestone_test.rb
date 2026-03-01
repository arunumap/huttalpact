require "test_helper"

class LeaseMilestoneTest < ActiveSupport::TestCase
  setup do
    @milestone = lease_milestones(:insurance_renewal)
    @overdue = lease_milestones(:overdue_milestone)
  end

  test "valid lease milestone" do
    assert @milestone.valid?
  end

  test "belongs to contract" do
    assert_equal contracts(:commercial_lease), @milestone.contract
  end

  test "acts as tenant" do
    assert_equal organizations(:one), @milestone.organization
  end

  test "requires milestone_type" do
    @milestone.milestone_type = nil
    assert_not @milestone.valid?
  end

  test "requires due_date" do
    @milestone.due_date = nil
    assert_not @milestone.valid?
  end

  test "validates milestone_type inclusion" do
    @milestone.milestone_type = "invalid"
    assert_not @milestone.valid?
  end

  test "validates recurrence_interval inclusion" do
    @milestone.recurrence_interval = "invalid"
    assert_not @milestone.valid?
  end

  test "upcoming scope returns future milestones" do
    contract = contracts(:commercial_lease)
    ActsAsTenant.with_tenant(organizations(:one)) do
      upcoming = contract.lease_milestones.upcoming
      upcoming.each do |ms|
        assert ms.due_date >= Date.current
      end
    end
  end

  test "overdue scope returns past-due milestones" do
    ActsAsTenant.with_tenant(organizations(:one)) do
      overdue = LeaseMilestone.overdue
      overdue.each do |ms|
        assert ms.due_date < Date.current
      end
    end
  end

  test "by_type scope filters correctly" do
    contract = contracts(:commercial_lease)
    ActsAsTenant.with_tenant(organizations(:one)) do
      cam_milestones = contract.lease_milestones.by_type("cam_reconciliation")
      assert cam_milestones.all? { |m| m.milestone_type == "cam_reconciliation" }
    end
  end

  test "overdue? returns true for past milestones" do
    assert @overdue.overdue?
  end

  test "overdue? returns false for future milestones" do
    assert_not @milestone.overdue?
  end

  test "urgent? returns true within 30 days" do
    @milestone.due_date = 15.days.from_now.to_date
    assert @milestone.urgent?
  end

  test "days_until_due calculates correctly" do
    expected = (@milestone.due_date - Date.current).to_i
    assert_equal expected, @milestone.days_until_due
  end

  test "next_occurrence_date advances recurring past milestones" do
    recurring = lease_milestones(:cam_reconciliation)
    next_date = recurring.next_occurrence_date
    assert next_date >= Date.current, "Next occurrence should be in the future"
  end

  test "next_occurrence_date returns due_date for non-recurring" do
    non_recurring = lease_milestones(:ti_completion)
    assert_equal non_recurring.due_date, non_recurring.next_occurrence_date
  end
end
