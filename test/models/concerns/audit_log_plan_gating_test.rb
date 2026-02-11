require "test_helper"

class AuditLogPlanGatingTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:one)
  end

  # plan_audit_log_days
  test "free plan has 7-day audit log limit" do
    @org.plan = "free"
    assert_equal 7, @org.plan_audit_log_days
  end

  test "starter plan has 30-day audit log limit" do
    @org.plan = "starter"
    assert_equal 30, @org.plan_audit_log_days
  end

  test "pro plan has no audit log limit" do
    @org.plan = "pro"
    assert_nil @org.plan_audit_log_days
  end

  # audit_log_cutoff_date
  test "free plan cutoff date is 7 days ago" do
    @org.plan = "free"
    expected = 7.days.ago
    assert_in_delta expected, @org.audit_log_cutoff_date, 2.seconds
  end

  test "starter plan cutoff date is 30 days ago" do
    @org.plan = "starter"
    expected = 30.days.ago
    assert_in_delta expected, @org.audit_log_cutoff_date, 2.seconds
  end

  test "pro plan cutoff date is nil" do
    @org.plan = "pro"
    assert_nil @org.audit_log_cutoff_date
  end

  # AuditLog.since scope
  test "since scope filters records older than date" do
    ActsAsTenant.with_tenant(@org) do
      old_log = AuditLog.create!(organization: @org, action: "created")
      old_log.update_column(:created_at, 10.days.ago)

      recent_log = AuditLog.create!(organization: @org, action: "viewed")
      recent_log.update_column(:created_at, 1.day.ago)

      results = AuditLog.since(7.days.ago)
      assert_includes results, recent_log
      assert_not_includes results, old_log
    end
  end

  test "since scope returns all records when date is nil" do
    ActsAsTenant.with_tenant(@org) do
      old_log = AuditLog.create!(organization: @org, action: "created")
      old_log.update_column(:created_at, 100.days.ago)

      results = AuditLog.since(nil)
      assert_includes results, old_log
    end
  end
end
