require "test_helper"

class ContractReviewCompletionServiceTest < ActiveSupport::TestCase
  setup do
    @contract = contracts(:hvac_maintenance)
    @organization = organizations(:one)
    @user = users(:one)
    @contract.update!(status: "in_review")
    @review = ActsAsTenant.with_tenant(@organization) do
      @contract.contract_reviews.create!(organization: @organization, review_trigger: "initial_extraction")
    end
  end

  test "completing review applies approved values activates alerts and leaves follow-through open" do
    old_alert = @contract.alerts.create!(
      organization: @organization,
      alert_type: "expiry_warning",
      trigger_date: 14.days.from_now.to_date,
      status: "pending",
      message: "Old expiry alert"
    )
    create_field("contract.end_date", extracted_value: "2028-12-31", approved_value: "2028-12-31", readiness_bucket: "looks_good", review_status: "confirmed", reviewed_by: @user, reviewed_at: Time.current)
    create_field("contract.notice_period_days", extracted_value: 45, approved_value: 45, readiness_bucket: "looks_good", review_status: "edited", reviewed_by: @user, reviewed_at: Time.current)
    create_field("lease_detail.percentage_rent_report_date", extracted_value: nil, approved_value: nil, readiness_bucket: "needs_review", review_status: "pending")

    completion = ContractReviewCompletionService.new(review: @review, user: @user).call

    assert_equal "completed", @review.reload.status
    assert_equal "active", @contract.reload.status
    assert_equal Date.new(2028, 12, 31), @contract.end_date
    assert_equal 45, @contract.notice_period_days
    assert_not Alert.exists?(old_alert.id)
    assert @contract.alerts.exists?
    assert_equal 1, @review.standard_priority_open_items_summary[:count]
    assert AuditLog.exists?(contract: @contract, action: "review_completed")
    assert AuditLog.exists?(contract: @contract, action: "review_alerts_activated")
    assert_not completion.activation_result.skipped
  end

  test "completion requires blocking items to be resolved" do
    create_field("contract.end_date", extracted_value: nil, approved_value: nil, readiness_bucket: "blocked", review_status: "pending")

    error = assert_raises(ContractReviewCompletionService::CompletionError) do
      ContractReviewCompletionService.new(review: @review, user: @user).call
    end

    assert_match(/Resolve 1 blocking item/, error.message)
    assert_equal "in_review", @contract.reload.status
    assert_equal "open", @review.reload.status
  end

  test "completion translates validation failures into a user facing error" do
    create_field("contract.end_date", extracted_value: "2028-12-31", approved_value: "2028-12-31", readiness_bucket: "looks_good", review_status: "confirmed")

    invalid_contract = @contract.dup
    invalid_contract.errors.add(:end_date, "must be after the start date")
    invalid_applier = Object.new
    invalid_applier.define_singleton_method(:call) do
      raise ActiveRecord::RecordInvalid.new(invalid_contract)
    end

    ContractReviewCanonicalApplier.stub(:new, ->(_review) { invalid_applier }) do
      error = assert_raises(ContractReviewCompletionService::CompletionError) do
        ContractReviewCompletionService.new(review: @review, user: @user).call
      end

      assert_match(/Cannot complete review/, error.message)
      assert_match(/End date must be after the start date/i, error.message)
    end
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
