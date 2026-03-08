require "test_helper"

class ContractReviewFieldsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @contract = contracts(:hvac_maintenance)
    @contract.update!(status: "in_review")
    @review = ActsAsTenant.with_tenant(@contract.organization) do
      @contract.contract_reviews.create!(organization: @contract.organization, review_trigger: "initial_extraction")
    end
  end

  test "confirm updates the field and writes an audit entry" do
    field = create_field("contract.end_date", extracted_value: "2028-12-31", current_value: @contract.end_date&.iso8601, readiness_bucket: "looks_good")

    assert_difference -> { AuditLog.where(action: "review_field_confirmed", contract: @contract).count }, 1 do
      patch contract_review_field_confirm_path(@contract, field)
    end

    assert_redirected_to contract_review_path(@contract, anchor: ActionView::RecordIdentifier.dom_id(field))
    assert_equal "confirmed", field.reload.review_status
    assert_equal "looks_good", field.readiness_bucket
  end

  test "editing a field updates the approved value" do
    field = create_field("contract.notice_period_days", extracted_value: nil, current_value: nil, readiness_bucket: "blocked")

    patch contract_review_field_path(@contract, field), params: {
      contract_review_field: {
        approved_value: "30",
        review_note: "Verified in the amendment"
      }
    }

    assert_redirected_to contract_review_path(@contract, anchor: ActionView::RecordIdentifier.dom_id(field))
    assert_equal "edited", field.reload.review_status
    assert_equal 30, field.approved_value
    assert_equal "Verified in the amendment", field.review_note
  end

  test "completed review still allows non-gating follow-through updates" do
    @contract.update!(status: "active")
    @review.update!(status: "completed", completed_at: 1.hour.ago)
    field = create_field("lease_detail.percentage_rent_report_date", extracted_value: nil, current_value: nil, readiness_bucket: "needs_review")

    patch contract_review_field_path(@contract, field), params: {
      contract_review_field: {
        approved_value: "2027-03-31"
      }
    }

    assert_redirected_to contract_review_path(@contract, anchor: ActionView::RecordIdentifier.dom_id(field))
    assert_equal "edited", field.reload.review_status
    assert_equal "2027-03-31", field.approved_value
  end

  private

  def create_field(field_key, **attributes)
    defaults = {
      contract: @contract,
      organization: @contract.organization,
      extracted_value: attributes[:approved_value],
      current_value: attributes[:current_value],
      approved_value: attributes[:approved_value],
      readiness_bucket: "pending",
      review_status: "pending"
    }

    @review.contract_review_fields.create!(defaults.merge(attributes).merge(field_key:))
  end
end
