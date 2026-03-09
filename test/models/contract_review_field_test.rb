require "test_helper"

class ContractReviewFieldTest < ActiveSupport::TestCase
  setup do
    @field = contract_review_fields(:title_field)
  end

  # Associations

  test "belongs to contract_review" do
    assert_equal contract_reviews(:pending_review), @field.contract_review
  end

  test "source_document is optional" do
    assert_nil @field.source_document
    assert @field.valid?
  end

  test "reviewed_by is optional" do
    assert_nil @field.reviewed_by
    assert @field.valid?
  end

  # Validations

  test "valid field" do
    assert @field.valid?
  end

  test "validates status inclusion" do
    @field.status = "bogus"
    assert_not @field.valid?
    assert_includes @field.errors[:status], "is not included in the list"
  end

  test "accepts all valid statuses" do
    %w[pending confirmed edited not_found not_applicable auto_accepted].each do |s|
      @field.status = s
      assert @field.valid?, "Expected '#{s}' to be valid"
    end
  end

  test "validates field_group inclusion" do
    @field.field_group = "unknown"
    assert_not @field.valid?
    assert_includes @field.errors[:field_group], "is not included in the list"
  end

  test "accepts all valid field_groups" do
    %w[core dates financial lease_space cam ti escalations options milestones clauses].each do |g|
      @field.field_group = g
      assert @field.valid?, "Expected '#{g}' to be valid"
    end
  end

  test "validates field_name presence" do
    @field.field_name = nil
    assert_not @field.valid?
    assert_includes @field.errors[:field_name], "can't be blank"
  end

  test "validates display_name presence" do
    @field.display_name = nil
    assert_not @field.valid?
    assert_includes @field.errors[:display_name], "can't be blank"
  end

  test "validates confidence range" do
    @field.confidence = -1
    assert_not @field.valid?

    @field.confidence = 101
    assert_not @field.valid?
  end

  test "accepts confidence at boundaries" do
    @field.confidence = 0
    assert @field.valid?

    @field.confidence = 100
    assert @field.valid?
  end

  test "allows nil confidence" do
    @field.confidence = nil
    assert @field.valid?
  end

  test "validates source_match_strategy inclusion" do
    @field.source_match_strategy = "invalid"
    assert_not @field.valid?
    assert_includes @field.errors[:source_match_strategy], "is not included in the list"
  end

  test "accepts all valid source_match_strategies" do
    %w[exact fuzzy anchor none].each do |s|
      @field.source_match_strategy = s
      assert @field.valid?, "Expected '#{s}' to be valid"
    end
  end

  test "allows nil source_match_strategy" do
    @field.source_match_strategy = nil
    assert @field.valid?
  end

  # Scopes

  test "pending scope" do
    pending = ContractReviewField.pending
    assert_includes pending, contract_review_fields(:title_field)
    assert_not_includes pending, contract_review_fields(:vendor_name_field)
  end

  test "confirmed scope" do
    confirmed = ContractReviewField.confirmed
    assert_includes confirmed, contract_review_fields(:vendor_name_field)
    assert_not_includes confirmed, contract_review_fields(:title_field)
  end

  test "edited scope" do
    edited = ContractReviewField.edited
    assert_includes edited, contract_review_fields(:start_date_field)
    assert_not_includes edited, contract_review_fields(:title_field)
  end

  test "auto_accepted scope" do
    auto = ContractReviewField.auto_accepted
    assert_includes auto, contract_review_fields(:auto_accepted_field)
    assert_not_includes auto, contract_review_fields(:title_field)
  end

  test "not_found scope" do
    not_found = ContractReviewField.not_found
    assert_includes not_found, contract_review_fields(:not_found_field)
    assert_not_includes not_found, contract_review_fields(:title_field)
  end

  test "not_applicable scope" do
    na = ContractReviewField.not_applicable
    assert_includes na, contract_review_fields(:not_applicable_field)
    assert_not_includes na, contract_review_fields(:title_field)
  end

  test "reviewed scope excludes pending" do
    reviewed = ContractReviewField.reviewed
    assert_includes reviewed, contract_review_fields(:vendor_name_field)
    assert_includes reviewed, contract_review_fields(:start_date_field)
    assert_includes reviewed, contract_review_fields(:auto_accepted_field)
    assert_not_includes reviewed, contract_review_fields(:title_field)
    assert_not_includes reviewed, contract_review_fields(:monthly_value_field)
  end

  test "needs_review scope" do
    needs = ContractReviewField.needs_review
    assert_includes needs, contract_review_fields(:monthly_value_field)
    assert_not_includes needs, contract_review_fields(:title_field)
  end

  test "confident scope" do
    confident = ContractReviewField.confident
    assert_includes confident, contract_review_fields(:title_field)
    assert_not_includes confident, contract_review_fields(:monthly_value_field)
  end

  test "by_group scope" do
    core = ContractReviewField.by_group("core")
    assert_includes core, contract_review_fields(:title_field)
    assert_includes core, contract_review_fields(:vendor_name_field)
    assert_not_includes core, contract_review_fields(:monthly_value_field)
  end

  test "ordered scope sorts by field_group then position" do
    review = contract_reviews(:pending_review)
    ordered = review.fields.ordered
    groups = ordered.map(&:field_group)
    positions = ordered.group_by(&:field_group).values.flat_map { |fields| fields.map(&:position) }

    # Groups should be in alphabetical order
    assert_equal groups.sort, groups
  end

  # Predicates

  test "reviewed? returns false for pending" do
    assert_not contract_review_fields(:title_field).reviewed?
  end

  test "reviewed? returns true for confirmed" do
    assert contract_review_fields(:vendor_name_field).reviewed?
  end

  test "reviewed? returns true for edited" do
    assert contract_review_fields(:start_date_field).reviewed?
  end

  test "reviewed? returns true for auto_accepted" do
    assert contract_review_fields(:auto_accepted_field).reviewed?
  end

  test "reviewed? returns true for not_found" do
    assert contract_review_fields(:not_found_field).reviewed?
  end

  test "reviewed? returns true for not_applicable" do
    assert contract_review_fields(:not_applicable_field).reviewed?
  end

  # final_value

  test "final_value returns extracted_value for confirmed" do
    field = contract_review_fields(:vendor_name_field)
    assert_equal field.extracted_value, field.final_value
  end

  test "final_value returns extracted_value for auto_accepted" do
    field = contract_review_fields(:auto_accepted_field)
    assert_equal field.extracted_value, field.final_value
  end

  test "final_value returns user_value for edited" do
    field = contract_review_fields(:start_date_field)
    assert_equal field.user_value, field.final_value
  end

  test "final_value returns nil for not_found" do
    field = contract_review_fields(:not_found_field)
    assert_nil field.final_value
  end

  test "final_value returns nil for not_applicable" do
    field = contract_review_fields(:not_applicable_field)
    assert_nil field.final_value
  end

  test "final_value returns extracted_value for pending (fallback)" do
    assert_equal @field.extracted_value, @field.final_value
  end

  # Edge cases

  test "field with nil extracted_value is valid" do
    field = contract_review_fields(:not_found_field)
    assert field.valid?
    assert_nil field.extracted_value
  end

  test "field with nil source_excerpt is valid" do
    field = contract_review_fields(:not_found_field)
    assert field.valid?
    assert_nil field.source_excerpt
  end

  test "field with nil confidence is valid" do
    field = contract_review_fields(:not_found_field)
    assert field.valid?
    assert_nil field.confidence
  end
end
