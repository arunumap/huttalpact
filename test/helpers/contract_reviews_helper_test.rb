require "test_helper"

class ContractReviewsHelperTest < ActionView::TestCase
  include ContractReviewsHelper

  test "uncertainty guidance includes best guess and validation prompt" do
    field = contract_review_fields(:monthly_value_field)
    field.source_excerpt = nil

    message = uncertainty_guidance_message(field)

    assert_includes message, "Confidence is moderate"
    assert_includes message, "Best guess: $5,400.00."
    assert_includes message, "Can you validate this against the document or edit it?"
  end

  test "uncertainty guidance is nil when source excerpt exists" do
    field = contract_review_fields(:monthly_value_field)

    assert_nil uncertainty_guidance_message(field)
  end

  test "uncertainty guidance is nil when field does not need review" do
    field = contract_review_fields(:title_field)
    field.source_excerpt = nil

    assert_nil uncertainty_guidance_message(field)
  end

  test "uncertainty guidance reflects low confidence wording" do
    field = contract_review_fields(:monthly_value_field)
    field.source_excerpt = nil
    field.confidence = 35

    message = uncertainty_guidance_message(field)

    assert_includes message, "Confidence is low"
  end

  test "uncertainty guidance handles missing confidence" do
    field = contract_review_fields(:monthly_value_field)
    field.source_excerpt = nil
    field.confidence = nil

    message = uncertainty_guidance_message(field)

    assert_includes message, "I couldn't find a direct quote for this value."
  end
end
