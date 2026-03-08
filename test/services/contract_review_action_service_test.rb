require "test_helper"

class ContractReviewActionServiceTest < ActiveSupport::TestCase
  setup do
    @contract = contracts(:hvac_maintenance)
    @organization = organizations(:one)
    @user = users(:one)
    @review = ActsAsTenant.with_tenant(@organization) do
      @contract.contract_reviews.create!(organization: @organization, review_trigger: "initial_extraction")
    end
    @service = ContractReviewActionService.new(review: @review, user: @user)
  end

  test "editing a field recalculates dependent derived fields and records audit history" do
    @contract.update!(next_renewal_date: nil)
    end_date_field = create_field("contract.end_date", extracted_value: "2027-12-31", approved_value: "2027-12-31", review_status: "confirmed", readiness_bucket: "looks_good", reviewed_by: @user, reviewed_at: Time.current)
    create_field("contract.auto_renews", extracted_value: false, approved_value: false, review_status: "confirmed", readiness_bucket: "looks_good", reviewed_by: @user, reviewed_at: Time.current)
    notice_field = create_field("contract.notice_period_days", extracted_value: nil, current_value: nil, readiness_bucket: "blocked")
    derived_field = create_field("notice_period_start_date", extracted_value: nil, current_value: nil, readiness_bucket: "blocked")
    conflict = notice_field.contract_review_conflicts.create!(
      contract_review: @review,
      contract: @contract,
      organization: @organization,
      conflict_type: "missing_extracted_value",
      blocks_activation: true,
      summary: "Notice period is missing."
    )

    @service.edit!(field: notice_field, raw_value: "45", note: "Addendum reduced the notice window")

    assert_equal "edited", notice_field.reload.review_status
    assert_equal 45, notice_field.approved_value
    assert_equal "looks_good", notice_field.readiness_bucket
    assert_equal "resolved", conflict.reload.status
    assert_equal "confirmed", derived_field.reload.review_status
    assert_equal "2027-11-16", derived_field.approved_value
    assert_equal [ "conflict_resolved", "edited" ], notice_field.contract_review_field_events.order(:created_at).pluck(:action).last(2)
    assert_includes derived_field.contract_review_field_events.pluck(:action), "recalculated"
    assert AuditLog.exists?(contract: @contract, action: "review_field_edited")
    assert_equal 0, @review.reload.blocked_fields_count
    assert_equal end_date_field.id, end_date_field.reload.id
  end

  test "bulk confirm only confirms pending safe fields" do
    safe_field = create_field("contract.end_date", extracted_value: "2027-12-31", readiness_bucket: "looks_good")
    create_field("contract.notice_period_days", extracted_value: 30, readiness_bucket: "needs_review")
    create_field("contract.status", extracted_value: "in_review", readiness_bucket: "looks_good")

    confirmed_count = @service.bulk_confirm_safe_items!

    assert_equal 1, confirmed_count
    assert_equal "confirmed", safe_field.reload.review_status
    assert_equal "pending", @review.contract_review_fields.find_by!(field_key: "contract.notice_period_days").review_status
    assert_equal "pending", @review.contract_review_fields.find_by!(field_key: "contract.status").review_status
    assert AuditLog.exists?(contract: @contract, action: "review_bulk_confirmed")
  end

  test "completed reviews reject activation driving edits" do
    field = create_field("contract.end_date", extracted_value: "2027-12-31", readiness_bucket: "looks_good")
    @review.update!(status: "completed", completed_at: Time.current)

    error = assert_raises(ContractReviewActionService::ActionError) do
      @service.edit!(field:, raw_value: "2028-01-15")
    end

    assert_match(/Activation-driving fields/, error.message)
    assert_equal "pending", field.reload.review_status
  end

  private

  def create_field(field_key, **attributes)
    defaults = {
      contract: @contract,
      organization: @organization,
      extracted_value: attributes[:approved_value],
      current_value: attributes[:current_value],
      approved_value: attributes[:approved_value],
      readiness_bucket: "pending",
      review_status: "pending"
    }

    @review.contract_review_fields.create!(defaults.merge(attributes).merge(field_key:))
  end
end
