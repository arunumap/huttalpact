require "test_helper"

class ContractReviewTest < ActiveSupport::TestCase
  setup do
    @review = contract_reviews(:pending_review)
  end

  # Associations

  test "belongs to contract" do
    assert_equal contracts(:hvac_maintenance), @review.contract
  end

  test "belongs to organization" do
    assert_equal organizations(:one), @review.organization
  end

  test "has many fields" do
    assert_respond_to @review, :fields
    assert_kind_of ContractReviewField, @review.fields.first
  end

  test "belongs to completed_by user" do
    completed = contract_reviews(:completed_review)
    assert_equal users(:one), completed.completed_by
  end

  test "completed_by is optional" do
    assert_nil @review.completed_by
    assert @review.valid?
  end

  test "destroying review destroys associated fields" do
    field_ids = @review.fields.pluck(:id)
    assert field_ids.any?

    @review.destroy!

    field_ids.each do |id|
      assert_not ContractReviewField.exists?(id)
    end
  end

  # Validations

  test "valid review" do
    assert @review.valid?
  end

  test "validates status inclusion" do
    @review.status = "invalid"
    assert_not @review.valid?
    assert_includes @review.errors[:status], "is not included in the list"
  end

  test "accepts all valid statuses" do
    %w[pending in_progress completed].each do |s|
      @review.status = s
      assert @review.valid?, "Expected '#{s}' to be valid"
    end
  end

  test "validates review_type inclusion" do
    @review.review_type = "partial"
    assert_not @review.valid?
    assert_includes @review.errors[:review_type], "is not included in the list"
  end

  test "accepts all valid review_types" do
    %w[full incremental].each do |t|
      @review.review_type = t
      assert @review.valid?, "Expected '#{t}' to be valid"
    end
  end

  test "validates confidence_threshold range" do
    @review.confidence_threshold = -1
    assert_not @review.valid?

    @review.confidence_threshold = 101
    assert_not @review.valid?
  end

  test "accepts confidence_threshold at boundaries" do
    @review.confidence_threshold = 0
    assert @review.valid?

    @review.confidence_threshold = 100
    assert @review.valid?
  end

  test "validates total_fields is non-negative" do
    @review.total_fields = -1
    assert_not @review.valid?
  end

  test "validates reviewed_fields is non-negative" do
    @review.reviewed_fields = -1
    assert_not @review.valid?
  end

  # Scopes

  test "pending scope" do
    pending = ContractReview.pending
    assert_includes pending, contract_reviews(:pending_review)
    assert_not_includes pending, contract_reviews(:in_progress_review)
    assert_not_includes pending, contract_reviews(:completed_review)
  end

  test "in_progress scope" do
    in_progress = ContractReview.in_progress
    assert_includes in_progress, contract_reviews(:in_progress_review)
    assert_not_includes in_progress, contract_reviews(:pending_review)
  end

  test "completed scope" do
    completed = ContractReview.completed
    assert_includes completed, contract_reviews(:completed_review)
    assert_not_includes completed, contract_reviews(:pending_review)
  end

  test "active scope includes pending and in_progress" do
    active = ContractReview.active
    assert_includes active, contract_reviews(:pending_review)
    assert_includes active, contract_reviews(:in_progress_review)
    assert_not_includes active, contract_reviews(:completed_review)
  end

  test "for_contract scope" do
    reviews = ContractReview.for_contract(contracts(:hvac_maintenance))
    assert_includes reviews, contract_reviews(:pending_review)
    assert_not_includes reviews, contract_reviews(:in_progress_review)
  end

  # Predicates

  test "completed? returns true for completed status" do
    assert contract_reviews(:completed_review).completed?
    assert_not contract_reviews(:pending_review).completed?
  end

  test "pending? returns true for pending status" do
    assert contract_reviews(:pending_review).pending?
    assert_not contract_reviews(:in_progress_review).pending?
  end

  test "in_progress? returns true for in_progress status" do
    assert contract_reviews(:in_progress_review).in_progress?
    assert_not contract_reviews(:pending_review).in_progress?
  end

  # Progress

  test "progress_percentage with zero total_fields" do
    @review.total_fields = 0
    @review.reviewed_fields = 0
    assert_equal 0, @review.progress_percentage
  end

  test "progress_percentage with partial progress" do
    in_progress = contract_reviews(:in_progress_review)
    assert_equal 50, in_progress.progress_percentage
  end

  test "progress_percentage at 100%" do
    completed = contract_reviews(:completed_review)
    assert_equal 100, completed.progress_percentage
  end

  test "progress_percentage rounds correctly" do
    @review.total_fields = 3
    @review.reviewed_fields = 1
    assert_equal 33, @review.progress_percentage
  end

  # all_required_fields_reviewed?

  test "all_required_fields_reviewed? returns false when needs_review pending fields exist" do
    # pending_review has monthly_value_field with needs_review: true, status: pending
    assert_not @review.all_required_fields_reviewed?
  end

  test "all_required_fields_reviewed? returns true when no needs_review pending fields" do
    completed = contract_reviews(:completed_review)
    assert completed.all_required_fields_reviewed?
  end

  test "all_required_fields_reviewed? returns true when review has no fields" do
    review = ContractReview.create!(
      contract: contracts(:expired_insurance),
      organization: organizations(:one),
      status: "pending",
      review_type: "full",
      confidence_threshold: 80,
      total_fields: 0,
      reviewed_fields: 0
    )
    assert review.all_required_fields_reviewed?
  end
end
