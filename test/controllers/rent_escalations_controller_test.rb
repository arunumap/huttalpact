require "test_helper"

class RentEscalationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @contract = contracts(:commercial_lease)
    @escalation = rent_escalations(:year_one)
  end

  # Auth
  test "redirects to login when not authenticated" do
    sign_out
    get new_contract_rent_escalation_path(@contract)
    assert_redirected_to new_session_path
  end

  # New
  test "should get new" do
    get new_contract_rent_escalation_path(@contract)
    assert_response :success
    assert_match "Add Rent Escalation", response.body
  end

  # Create
  test "should create rent escalation" do
    assert_difference "RentEscalation.count", 1 do
      post contract_rent_escalations_path(@contract), params: {
        rent_escalation: {
          effective_date: "2029-01-01",
          base_rent_monthly: 10000,
          base_rent_annual: 120000,
          escalation_type: "fixed_percentage",
          escalation_value: 3.0,
          description: "3% annual increase"
        }
      }
    end
    assert_redirected_to @contract
    assert_equal "Rent escalation added.", flash[:notice]
  end

  test "create with invalid params renders new" do
    assert_no_difference "RentEscalation.count" do
      post contract_rent_escalations_path(@contract), params: {
        rent_escalation: { effective_date: nil, escalation_type: "flat" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "create logs audit" do
    assert_difference "AuditLog.count" do
      post contract_rent_escalations_path(@contract), params: {
        rent_escalation: {
          effective_date: "2029-01-01",
          escalation_type: "flat",
          base_rent_monthly: 10000
        }
      }
    end
  end

  # Edit
  test "should get edit" do
    get edit_contract_rent_escalation_path(@contract, @escalation)
    assert_response :success
    assert_match "Edit Rent Escalation", response.body
  end

  # Update
  test "should update rent escalation" do
    patch contract_rent_escalation_path(@contract, @escalation), params: {
      rent_escalation: { base_rent_monthly: 9000 }
    }
    assert_redirected_to @contract
    assert_equal "Rent escalation updated.", flash[:notice]
    @escalation.reload
    assert_equal 9000, @escalation.base_rent_monthly.to_i
  end

  test "update with invalid params renders edit" do
    patch contract_rent_escalation_path(@contract, @escalation), params: {
      rent_escalation: { escalation_type: "invalid" }
    }
    assert_response :unprocessable_entity
  end

  # Destroy
  test "should destroy rent escalation" do
    assert_difference "RentEscalation.count", -1 do
      delete contract_rent_escalation_path(@contract, @escalation)
    end
    assert_redirected_to @contract
    assert_equal "Rent escalation removed.", flash[:notice]
  end

  # Tenant isolation
  test "cannot access other organization escalations" do
    other_contract = contracts(:other_org_contract)
    get new_contract_rent_escalation_path(other_contract)
    assert_response :redirect
  end
end
