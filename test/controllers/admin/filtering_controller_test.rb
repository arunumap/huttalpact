require "test_helper"

class Admin::FilteringControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin_user = admin_users(:one)
    sign_in_as_admin(@admin_user)
  end

  test "audit logs filters by organization and action" do
    get admin_audit_logs_path, params: { organization_id: organizations(:one).id, action_type: "updated" }

    assert_response :success
    assert_includes response.body, "Updated fields: end_date, status"
    assert_not_includes response.body, "Created contract in other org"
  end

  test "audit logs date filter returns empty state when no rows" do
    get admin_audit_logs_path, params: { start_date: 1.year.from_now.to_date.to_s, end_date: 1.year.from_now.to_date.to_s }

    assert_response :success
    assert_includes response.body, "No audit logs match the selected filters."
  end

  test "ai usage filters by organization" do
    org_one = organizations(:one)
    org_two = organizations(:two)

    AiUsageLog.create!(
      organization: org_one,
      contract: contracts(:hvac_maintenance),
      ai_model: "claude-sonnet-4-20250514",
      input_tokens: 100,
      output_tokens: 50,
      extraction_mode: "full",
      success: true
    )

    AiUsageLog.create!(
      organization: org_two,
      contract: contracts(:other_org_contract),
      ai_model: "org-two-only-model",
      input_tokens: 200,
      output_tokens: 100,
      extraction_mode: "full",
      success: true
    )

    get admin_ai_usage_index_path, params: { organization_id: org_one.id }

    assert_response :success
    assert_includes response.body, "claude-sonnet-4-20250514"
    assert_not_includes response.body, "org-two-only-model"
  end
end
