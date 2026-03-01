require "test_helper"

class LeaseOptionTest < ActiveSupport::TestCase
  setup do
    @renewal = lease_options(:renewal_option)
    @termination = lease_options(:termination_option)
  end

  test "valid lease option" do
    assert @renewal.valid?
  end

  test "belongs to contract" do
    assert_equal contracts(:commercial_lease), @renewal.contract
  end

  test "requires option_type" do
    @renewal.option_type = nil
    assert_not @renewal.valid?
  end

  test "validates option_type inclusion" do
    @renewal.option_type = "invalid"
    assert_not @renewal.valid?
  end

  test "validates penalty_amount non-negative" do
    @termination.penalty_amount = -1
    assert_not @termination.valid?
  end

  test "upcoming scope returns future notice deadlines" do
    contract = contracts(:commercial_lease)
    upcoming = contract.lease_options.upcoming
    upcoming.each do |opt|
      assert opt.notice_deadline >= Date.current if opt.notice_deadline.present?
    end
  end

  test "by_type scope filters correctly" do
    contract = contracts(:commercial_lease)
    renewals = contract.lease_options.by_type("renewal")
    assert renewals.all? { |o| o.option_type == "renewal" }
  end

  test "days_until_notice_deadline calculates correctly" do
    days = @termination.days_until_notice_deadline
    assert_kind_of Integer, days
    assert days > 0
  end

  test "days_until_notice_deadline returns nil without deadline" do
    @renewal.notice_deadline = nil
    assert_nil @renewal.days_until_notice_deadline
  end

  test "notice_deadline_passed? returns false for future deadline" do
    assert_not @termination.notice_deadline_passed?
  end

  test "urgent? returns true for near deadline" do
    @termination.notice_deadline = 30.days.from_now.to_date
    assert @termination.urgent?
  end

  test "urgent? returns false for distant deadline" do
    @termination.notice_deadline = 365.days.from_now.to_date
    assert_not @termination.urgent?
  end

  test "term_length_label formats months" do
    assert_equal "5 years", @renewal.term_length_label
  end

  test "term_length_label returns nil without months" do
    @renewal.term_length_months = nil
    assert_nil @renewal.term_length_label
  end

  test "option_type_label returns human-readable label" do
    assert_equal "Renewal", @renewal.option_type_label
    assert_equal "Right of First Refusal", LeaseOption.new(option_type: "rofr").option_type_label
  end
end
