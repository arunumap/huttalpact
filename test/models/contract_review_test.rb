require "test_helper"

class ContractReviewTest < ActiveSupport::TestCase
  setup do
    @organization = organizations(:one)
    @contract = contracts(:commercial_lease)
  end

  test "assigns organization from contract" do
    review = ContractReview.new(contract: @contract)

    assert review.valid?
    assert_equal @organization, review.organization
  end

  test "prevents more than one open review per contract" do
    create_review

    duplicate = ContractReview.new(contract: @contract, organization: @organization, status: "open")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:contract_id], "already has an open review"
  end

  test "allows a new open review after the prior one is completed" do
    first_review = create_review
    first_review.update!(status: "completed", completed_at: Time.current)

    next_review = ContractReview.new(contract: @contract, review_trigger: "addendum_upload")

    assert next_review.valid?
  end

  test "current_contract_review returns the open review" do
    completed_review = create_review(review_trigger: "initial_extraction")
    completed_review.update!(status: "completed", completed_at: Time.current)

    open_review = create_review(review_trigger: "addendum_upload")

    assert_equal open_review, @contract.reload.current_contract_review
  end

  test "tracks summary counts from review fields and conflicts" do
    review = create_review

    pending_field = create_field(review:, field_key: "contract.auto_renews", readiness_bucket: "pending")
    create_field(review:, field_key: "contract.end_date", readiness_bucket: "looks_good")
    create_field(review:, field_key: "contract.next_renewal_date", readiness_bucket: "needs_review")
    create_field(review:, field_key: "contract.notice_period_days", readiness_bucket: "blocked")
    create_conflict(review:, field: pending_field)

    review.reload

    assert_equal 4, review.total_fields_count
    assert_equal 1, review.pending_fields_count
    assert_equal 1, review.looks_good_fields_count
    assert_equal 1, review.needs_review_fields_count
    assert_equal 1, review.blocked_fields_count
    assert_equal 1, review.open_conflicts_count
  end

  test "requires ai usage logs to match the review contract" do
    other_log = create_ai_usage_log(contract: contracts(:hvac_maintenance))
    review = ContractReview.new(contract: @contract, ai_usage_log: other_log)

    assert_not review.valid?
    assert_includes review.errors[:ai_usage_log], "must belong to the same contract"
  end

  private

  def create_review(contract: @contract, review_trigger: "initial_extraction")
    ActsAsTenant.with_tenant(contract.organization) do
      ContractReview.create!(
        contract:,
        organization: contract.organization,
        review_trigger:
      )
    end
  end

  def create_field(review:, field_key:, readiness_bucket:)
    ActsAsTenant.with_tenant(review.organization) do
      ContractReviewField.create!(
        contract_review: review,
        field_key:,
        readiness_bucket:
      )
    end
  end

  def create_conflict(review:, field:)
    ActsAsTenant.with_tenant(review.organization) do
      ContractReviewConflict.create!(
        contract_review: review,
        contract_review_field: field,
        conflict_type: "value_mismatch",
        summary: "Extracted value differs from the approved value."
      )
    end
  end

  def create_ai_usage_log(contract:)
    AiUsageLog.create!(
      organization: contract.organization,
      contract:,
      ai_model: "claude-sonnet-4",
      input_tokens: 1200,
      output_tokens: 300,
      extraction_mode: "full"
    )
  end
end
