require "test_helper"

class LeaseOptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @contract = contracts(:commercial_lease)
    @option = lease_options(:renewal_option)
  end

  # Auth
  test "redirects to login when not authenticated" do
    sign_out
    get new_contract_lease_option_path(@contract)
    assert_redirected_to new_session_path
  end

  # New
  test "should get new" do
    get new_contract_lease_option_path(@contract)
    assert_response :success
    assert_match "Add Lease Option", response.body
  end

  # Create
  test "should create lease option" do
    assert_difference "LeaseOption.count", 1 do
      post contract_lease_options_path(@contract), params: {
        lease_option: {
          option_type: "rofr",
          exercise_deadline: "2029-12-31",
          notice_deadline: "2029-06-30",
          conditions: "Right of first refusal on adjacent space"
        }
      }
    end
    assert_redirected_to @contract
    assert_equal "Lease option added.", flash[:notice]
  end

  test "create enqueues alert generation job" do
    assert_enqueued_with(job: GenerateContractAlertsJob) do
      post contract_lease_options_path(@contract), params: {
        lease_option: {
          option_type: "renewal",
          exercise_deadline: "2031-01-01"
        }
      }
    end
  end

  test "create with invalid params renders new" do
    assert_no_difference "LeaseOption.count" do
      post contract_lease_options_path(@contract), params: {
        lease_option: { option_type: "invalid_type" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "create logs audit" do
    assert_difference "AuditLog.count" do
      post contract_lease_options_path(@contract), params: {
        lease_option: {
          option_type: "expansion",
          exercise_deadline: "2029-12-31"
        }
      }
    end
  end

  # Edit
  test "should get edit" do
    get edit_contract_lease_option_path(@contract, @option)
    assert_response :success
    assert_match "Edit Lease Option", response.body
  end

  # Update
  test "should update lease option" do
    patch contract_lease_option_path(@contract, @option), params: {
      lease_option: { term_length_months: 36, rent_terms: "Market rate" }
    }
    assert_redirected_to @contract
    assert_equal "Lease option updated.", flash[:notice]
    @option.reload
    assert_equal 36, @option.term_length_months
    assert_equal "Market rate", @option.rent_terms
  end

  test "update enqueues alert generation job" do
    assert_enqueued_with(job: GenerateContractAlertsJob) do
      patch contract_lease_option_path(@contract, @option), params: {
        lease_option: { term_length_months: 48 }
      }
    end
  end

  test "update with invalid params renders edit" do
    patch contract_lease_option_path(@contract, @option), params: {
      lease_option: { option_type: "invalid" }
    }
    assert_response :unprocessable_entity
  end

  # Destroy
  test "should destroy lease option" do
    assert_difference "LeaseOption.count", -1 do
      delete contract_lease_option_path(@contract, @option)
    end
    assert_redirected_to @contract
    assert_equal "Lease option removed.", flash[:notice]
  end

  test "destroy enqueues alert generation job" do
    assert_enqueued_with(job: GenerateContractAlertsJob) do
      delete contract_lease_option_path(@contract, @option)
    end
  end

  # Tenant isolation
  test "cannot access other organization options" do
    other_contract = contracts(:other_org_contract)
    get new_contract_lease_option_path(other_contract)
    assert_response :redirect
  end
end
