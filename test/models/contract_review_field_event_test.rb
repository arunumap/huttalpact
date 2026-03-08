require "test_helper"

class ContractReviewFieldEventTest < ActiveSupport::TestCase
  setup do
    @organization = organizations(:one)
    @review = ActsAsTenant.with_tenant(@organization) do
      ContractReview.create!(contract: contracts(:commercial_lease))
    end
    @field = ActsAsTenant.with_tenant(@organization) do
      ContractReviewField.create!(contract_review: @review, field_key: "contract.end_date")
    end
  end

  test "inherits review context from the field" do
    event = create_event

    assert_equal @review, event.contract_review
    assert_equal @field.contract, event.contract
    assert_equal @organization, event.organization
  end

  test "stores multiple events for the same field" do
    create_event(action: "extracted")
    create_event(action: "confirmed", user: users(:one), to_review_status: "confirmed")

    assert_equal %w[confirmed extracted].sort, @field.contract_review_field_events.pluck(:action).sort
    assert_equal 2, @field.contract_review_field_events.count
  end

  test "rejects unknown actions" do
    event = ContractReviewFieldEvent.new(contract_review_field: @field, action: "invalid_action")

    assert_not event.valid?
    assert_includes event.errors[:action], "is not included in the list"
  end

  private

  def create_event(action: "extracted", user: nil, to_review_status: nil)
    ActsAsTenant.with_tenant(@organization) do
      ContractReviewFieldEvent.create!(
        contract_review_field: @field,
        contract_review: @review,
        action:,
        user:,
        to_review_status:
      )
    end
  end
end
