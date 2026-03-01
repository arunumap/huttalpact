require "test_helper"

class LeaseDetailsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @contract = contracts(:commercial_lease)
    @lease_detail = lease_details(:commercial_lease_detail)
  end

  # Auth
  test "redirects to login when not authenticated" do
    sign_out
    get edit_contract_lease_detail_path(@contract)
    assert_redirected_to new_session_path
  end

  # Edit
  test "should get edit" do
    get edit_contract_lease_detail_path(@contract)
    assert_response :success
    assert_match "Edit Lease Details", response.body
  end

  test "edit builds lease_detail if none exists" do
    @contract.lease_detail.destroy
    get edit_contract_lease_detail_path(@contract)
    assert_response :success
  end

  # Update
  test "should update lease_detail" do
    patch contract_lease_detail_path(@contract), params: {
      lease_detail: { rentable_sqft: 4000, lease_type: "gross" }
    }
    assert_redirected_to @contract
    assert_equal "Lease details updated.", flash[:notice]
    @lease_detail.reload
    assert_equal 4000, @lease_detail.rentable_sqft.to_i
    assert_equal "gross", @lease_detail.lease_type
  end

  test "update creates audit log" do
    assert_difference "AuditLog.count" do
      patch contract_lease_detail_path(@contract), params: {
        lease_detail: { rentable_sqft: 5000 }
      }
    end
  end

  test "update with invalid params renders edit" do
    patch contract_lease_detail_path(@contract), params: {
      lease_detail: { lease_type: "invalid_type" }
    }
    assert_response :unprocessable_entity
  end

  test "update all CAM fields" do
    patch contract_lease_detail_path(@contract), params: {
      lease_detail: {
        cam_base_amount: 15000,
        cam_base_year: 2026,
        cam_cap_percentage: 6.0,
        cam_cap_type: "non_cumulative",
        cam_audit_rights: true,
        cam_gross_up_provision: false
      }
    }
    assert_redirected_to @contract
    @lease_detail.reload
    assert_equal 15000, @lease_detail.cam_base_amount.to_i
    assert_equal "non_cumulative", @lease_detail.cam_cap_type
  end

  test "update TI fields" do
    patch contract_lease_detail_path(@contract), params: {
      lease_detail: {
        ti_allowance_psf: 45.00,
        ti_total_amount: 157500,
        ti_deadline: 1.year.from_now.to_date,
        ti_disbursement_type: "reimbursement"
      }
    }
    assert_redirected_to @contract
    @lease_detail.reload
    assert_equal "reimbursement", @lease_detail.ti_disbursement_type
  end

  # Tenant isolation
  test "cannot access other organization lease details" do
    other_contract = contracts(:other_org_contract)
    get edit_contract_lease_detail_path(other_contract)
    assert_response :redirect
  end
end
