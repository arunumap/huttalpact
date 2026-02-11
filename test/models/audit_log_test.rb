require "test_helper"

class AuditLogTest < ActiveSupport::TestCase
  setup do
    @audit_log = audit_logs(:contract_created)
  end

  test "valid audit log" do
    assert @audit_log.valid?
  end

  test "requires action" do
    @audit_log.action = nil
    assert_not @audit_log.valid?
  end

  test "validates action inclusion" do
    @audit_log.action = "invalid_action"
    assert_not @audit_log.valid?
  end

  test "all actions are valid" do
    AuditLog::ACTIONS.each do |action|
      @audit_log.action = action
      assert @audit_log.valid?, "#{action} should be a valid action"
    end
  end

  test "belongs to organization" do
    assert_respond_to @audit_log, :organization
    assert_not_nil @audit_log.organization
  end

  test "user is optional" do
    @audit_log.user = nil
    assert @audit_log.valid?
  end

  test "contract is optional" do
    @audit_log.contract = nil
    assert @audit_log.valid?
  end

  test "recent scope orders by created_at desc" do
    logs = AuditLog.recent
    assert logs.first.created_at >= logs.last.created_at
  end

  test "for_contract scope" do
    contract = contracts(:hvac_maintenance)
    logs = AuditLog.for_contract(contract)
    assert logs.all? { |l| l.contract_id == contract.id }
  end

  test "for_action scope" do
    logs = AuditLog.for_action("created")
    assert logs.all? { |l| l.action == "created" }
  end

  test "for_user scope" do
    user = users(:one)
    logs = AuditLog.for_user(user)
    assert logs.all? { |l| l.user_id == user.id }
  end

  test "action_label returns titleized label" do
    assert_equal "Created", audit_logs(:contract_created).action_label
    assert_equal "Viewed", audit_logs(:contract_viewed).action_label
  end

  test "action_label handles alert_sent" do
    log = AuditLog.new(action: "alert_sent")
    assert_equal "Alert Sent", log.action_label
  end

  test "acts_as_tenant scopes to organization" do
    ActsAsTenant.with_tenant(organizations(:one)) do
      assert AuditLog.exists?(id: audit_logs(:contract_created).id)
      assert_not AuditLog.exists?(id: audit_logs(:other_org_log).id)
    end
  end
end
