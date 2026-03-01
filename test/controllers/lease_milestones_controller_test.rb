require "test_helper"

class LeaseMilestonesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @contract = contracts(:commercial_lease)
    @milestone = lease_milestones(:cam_reconciliation)
  end

  # Auth
  test "redirects to login when not authenticated" do
    sign_out
    get new_contract_lease_milestone_path(@contract)
    assert_redirected_to new_session_path
  end

  # New
  test "should get new" do
    get new_contract_lease_milestone_path(@contract)
    assert_response :success
    assert_match "Add Lease Milestone", response.body
  end

  # Create
  test "should create lease milestone" do
    assert_difference "LeaseMilestone.count", 1 do
      post contract_lease_milestones_path(@contract), params: {
        lease_milestone: {
          milestone_type: "custom",
          due_date: 60.days.from_now.to_date,
          description: "Quarterly review meeting",
          recurring: true,
          recurrence_interval: "quarterly"
        }
      }
    end
    assert_redirected_to @contract
    assert_equal "Lease milestone added.", flash[:notice]

    milestone = LeaseMilestone.order(created_at: :desc).first
    assert_equal @contract.organization, milestone.organization
  end

  test "create enqueues alert generation job" do
    assert_enqueued_with(job: GenerateContractAlertsJob) do
      post contract_lease_milestones_path(@contract), params: {
        lease_milestone: {
          milestone_type: "custom",
          due_date: 30.days.from_now.to_date,
          description: "Test"
        }
      }
    end
  end

  test "create with invalid params renders new" do
    assert_no_difference "LeaseMilestone.count" do
      post contract_lease_milestones_path(@contract), params: {
        lease_milestone: { milestone_type: "invalid_type", due_date: nil }
      }
    end
    assert_response :unprocessable_entity
  end

  test "create logs audit" do
    assert_difference "AuditLog.count" do
      post contract_lease_milestones_path(@contract), params: {
        lease_milestone: {
          milestone_type: "custom",
          due_date: 30.days.from_now.to_date,
          description: "Audit test"
        }
      }
    end
  end

  # Edit
  test "should get edit" do
    get edit_contract_lease_milestone_path(@contract, @milestone)
    assert_response :success
    assert_match "Edit Lease Milestone", response.body
  end

  # Update
  test "should update lease milestone" do
    patch contract_lease_milestone_path(@contract, @milestone), params: {
      lease_milestone: { description: "Updated description", recurrence_interval: "quarterly" }
    }
    assert_redirected_to @contract
    assert_equal "Lease milestone updated.", flash[:notice]
    @milestone.reload
    assert_equal "Updated description", @milestone.description
    assert_equal "quarterly", @milestone.recurrence_interval
  end

  test "update enqueues alert generation job" do
    assert_enqueued_with(job: GenerateContractAlertsJob) do
      patch contract_lease_milestone_path(@contract, @milestone), params: {
        lease_milestone: { description: "Updated" }
      }
    end
  end

  test "update with invalid params renders edit" do
    patch contract_lease_milestone_path(@contract, @milestone), params: {
      lease_milestone: { milestone_type: "nonexistent" }
    }
    assert_response :unprocessable_entity
  end

  # Destroy
  test "should destroy lease milestone" do
    assert_difference "LeaseMilestone.count", -1 do
      delete contract_lease_milestone_path(@contract, @milestone)
    end
    assert_redirected_to @contract
    assert_equal "Lease milestone removed.", flash[:notice]
  end

  test "destroy enqueues alert generation job" do
    assert_enqueued_with(job: GenerateContractAlertsJob) do
      delete contract_lease_milestone_path(@contract, @milestone)
    end
  end

  # Tenant isolation
  test "cannot access other organization milestones" do
    other_contract = contracts(:other_org_contract)
    get new_contract_lease_milestone_path(other_contract)
    assert_response :redirect
  end
end
