require "test_helper"

class ContractReviewFieldTest < ActiveSupport::TestCase
  setup do
    @organization = organizations(:one)
    @review = ActsAsTenant.with_tenant(@organization) do
      ContractReview.create!(contract: contracts(:commercial_lease))
    end
  end

  test "hydrates catalog metadata from the field key" do
    field = create_field(field_key: "contract.end_date")

    assert_equal "alert_date", field.field_family
    assert_equal "alert_driving", field.classification
    assert_equal "direct", field.source_type
    assert_equal %w[expiry_warning notice_period_start], field.alert_family_keys
    assert_equal [], field.derived_dependency_keys
    assert field.gates_activation?
  end

  test "rejects field keys that are not in the catalog" do
    field = ContractReviewField.new(contract_review: @review, field_key: "contract.unknown_field")

    assert_not field.valid?
    assert_includes field.errors[:field_key], "is not included in the review field catalog"
  end

  test "repeatable fields require an index and enforce uniqueness per position" do
    missing_index = ContractReviewField.new(contract_review: @review, field_key: "rent_escalation.effective_date")

    assert_not missing_index.valid?
    assert_includes missing_index.errors[:field_index], "can't be blank"

    create_field(field_key: "rent_escalation.effective_date", field_index: 0)
    create_field(field_key: "rent_escalation.effective_date", field_index: 1)

    duplicate = ContractReviewField.new(
      contract_review: @review,
      field_key: "rent_escalation.effective_date",
      field_index: 1
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:field_index], "already exists for this repeatable field"
  end

  test "effective_value prefers the approved value when present" do
    field = create_field(
      field_key: "contract.next_renewal_date",
      extracted_value: "2030-12-31",
      approved_value: "2031-01-31"
    )

    assert_equal "2031-01-31", field.effective_value
  end

  test "tenant scoping keeps review fields isolated by organization" do
    other_review = ActsAsTenant.with_tenant(organizations(:two)) do
      ContractReview.create!(contract: contracts(:other_org_contract))
    end

    own_field = create_field(field_key: "contract.end_date")
    other_field = ActsAsTenant.with_tenant(organizations(:two)) do
      ContractReviewField.create!(contract_review: other_review, field_key: "contract.end_date")
    end

    ActsAsTenant.with_tenant(@organization) do
      assert_includes ContractReviewField.all, own_field
      assert_not_includes ContractReviewField.all, other_field
    end
  end

  test "schema includes source and uniqueness indexes needed for review queries" do
    columns = ContractReviewField.column_names
    index_names = ActiveRecord::Base.connection.indexes(:contract_review_fields).map(&:name)

    assert_includes columns, "extracted_value"
    assert_includes columns, "approved_value"
    assert_includes columns, "source_span"
    assert_includes columns, "derived_dependency_keys"
    assert_includes columns, "alert_family_keys"
    assert_includes columns, "gates_activation"
    assert_includes index_names, "index_review_fields_on_review_and_key"
    assert_includes index_names, "index_review_fields_on_review_key_index"
    assert_includes index_names, "index_review_fields_on_org_review_readiness"
  end

  private

  def create_field(field_key:, field_index: nil, extracted_value: nil, approved_value: nil)
    ActsAsTenant.with_tenant(@organization) do
      ContractReviewField.create!(
        contract_review: @review,
        field_key:,
        field_index:,
        extracted_value:,
        approved_value:
      )
    end
  end
end
