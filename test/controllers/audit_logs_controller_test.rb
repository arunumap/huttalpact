require "test_helper"

class AuditLogsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
  end

  test "index renders successfully" do
    get audit_logs_path
    assert_response :success
    assert_select "h2", "Activity Log"
  end

  test "index shows audit log entries" do
    get audit_logs_path
    assert_response :success
    assert_select "table tbody tr"
  end

  test "index filters by action_type" do
    get audit_logs_path(action_type: "created")
    assert_response :success
  end

  test "index is tenant-scoped" do
    get audit_logs_path
    assert_response :success
    # Should not see other org's logs
    assert_no_match audit_logs(:other_org_log).details, response.body
  end

  test "requires authentication" do
    sign_out
    get audit_logs_path
    assert_response :redirect
  end

  test "free plan only sees last 7 days of logs" do
    org = organizations(:one)
    org.update!(plan: "free")

    old_log = AuditLog.create!(organization: org, action: "created", details: "OLD_LOG_MARKER")
    old_log.update_column(:created_at, 10.days.ago)

    recent_log = AuditLog.create!(organization: org, action: "viewed", details: "RECENT_LOG_MARKER")
    recent_log.update_column(:created_at, 1.day.ago)

    get audit_logs_path
    assert_response :success
    assert_match "RECENT_LOG_MARKER", response.body
    assert_no_match "OLD_LOG_MARKER", response.body
  end

  test "free plan shows upgrade banner" do
    org = organizations(:one)
    org.update!(plan: "free")

    get audit_logs_path
    assert_response :success
    assert_match "7 days", response.body
    assert_match "Upgrade for more history", response.body
    assert_match "View plans", response.body
  end

  test "pro plan sees all logs without banner" do
    org = organizations(:one)
    org.update!(plan: "pro")

    old_log = AuditLog.create!(organization: org, action: "created", details: "PRO_OLD_LOG")
    old_log.update_column(:created_at, 60.days.ago)

    get audit_logs_path
    assert_response :success
    assert_match "PRO_OLD_LOG", response.body
    assert_no_match "Upgrade for more history", response.body
  end

  test "starter plan sees 30 days of logs" do
    org = organizations(:one)
    org.update!(plan: "starter")

    within_log = AuditLog.create!(organization: org, action: "created", details: "STARTER_WITHIN")
    within_log.update_column(:created_at, 20.days.ago)

    outside_log = AuditLog.create!(organization: org, action: "viewed", details: "STARTER_OUTSIDE")
    outside_log.update_column(:created_at, 35.days.ago)

    get audit_logs_path
    assert_response :success
    assert_match "STARTER_WITHIN", response.body
    assert_no_match "STARTER_OUTSIDE", response.body
    assert_match "30 days", response.body
  end

  test "contract CRUD creates audit logs" do
    # Create
    assert_difference "AuditLog.count" do
      post contracts_path, params: {
        contract: {
          title: "Audit Test Contract",
          vendor_name: "Test Vendor",
          direction: "outbound",
          status: "active"
        }
      }
    end

    contract = Contract.last
    log = AuditLog.last
    assert_equal "created", log.action
    assert_equal contract.id, log.contract_id

    # View
    assert_difference "AuditLog.count" do
      get contract_path(contract)
    end
    assert_equal "viewed", AuditLog.last.action

    # Update
    assert_difference "AuditLog.count" do
      patch contract_path(contract), params: {
        contract: { vendor_name: "Updated Vendor" }
      }
    end
    assert_equal "updated", AuditLog.last.action

    # Delete
    assert_difference "AuditLog.count" do
      delete contract_path(contract)
    end
    assert_equal "deleted", AuditLog.last.action
  end
end
