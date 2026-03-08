require "test_helper"

class ContractReviewConflictTest < ActiveSupport::TestCase
  setup do
    @organization = organizations(:one)
    @review = ActsAsTenant.with_tenant(@organization) do
      ContractReview.create!(contract: contracts(:commercial_lease))
    end
    @field = ActsAsTenant.with_tenant(@organization) do
      ContractReviewField.create!(contract_review: @review, field_key: "contract.end_date")
    end
  end

  test "inherits review context and alert families from the field" do
    conflict = create_conflict

    assert_equal @review, conflict.contract_review
    assert_equal @field.contract, conflict.contract
    assert_equal @organization, conflict.organization
    assert_equal @field.alert_family_keys, conflict.alert_family_keys
  end

  test "allows multiple conflicts over time for the same field" do
    open_conflict = create_conflict
    resolved_conflict = create_conflict(status: "resolved", summary: "Prior mismatch has been resolved.")

    assert_equal 2, @field.contract_review_conflicts.count
    assert_includes ContractReviewConflict.open, open_conflict
    assert_includes ContractReviewConflict.resolved, resolved_conflict
  end

  test "rejects unknown conflict types" do
    conflict = ContractReviewConflict.new(
      contract_review_field: @field,
      conflict_type: "unknown_conflict",
      summary: "Invalid conflict"
    )

    assert_not conflict.valid?
    assert_includes conflict.errors[:conflict_type], "is not included in the list"
  end

  private

  def create_conflict(status: "open", summary: "Extracted value differs from the approved value.")
    ActsAsTenant.with_tenant(@organization) do
      ContractReviewConflict.create!(
        contract_review_field: @field,
        contract_review: @review,
        conflict_type: "value_mismatch",
        status:,
        summary:
      )
    end
  end
end
