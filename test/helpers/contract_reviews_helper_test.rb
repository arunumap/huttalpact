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

  test "milestone labels preserve CAM acronym" do
    assert_equal "CAM Reconciliation", milestone_type_label("cam_reconciliation")
  end

  test "milestone items parse from field final value" do
    field = contract_review_fields(:title_field)
    field.field_name = "lease_milestones"
    field.extracted_value = [
      { milestone_type: "insurance_renewal", due_date: "2025-08-01", description: "Renew policy", recurring: true, recurrence_interval: "annual" }
    ].to_json
    field.status = "pending"

    milestones = milestone_items(field)

    assert_equal 1, milestones.length
    assert_equal "insurance_renewal", milestones.first["milestone_type"]
    assert_equal "2025-08-01", milestones.first["due_date"]
  end

  test "milestone summary and purpose are human friendly" do
    milestone = {
      "milestone_type" => "insurance_renewal",
      "due_date" => "2025-08-01",
      "description" => "Renew policy",
      "recurring" => true,
      "recurrence_interval" => "annual"
    }

    assert_includes milestone_summary(milestone), "Insurance Renewal"
    assert_includes milestone_summary(milestone), "August 01, 2025"
    assert_includes milestone_purpose_text(milestone), "insurance"
    assert_equal "Repeats annual", milestone_recurrence_label(milestone)
  end

  test "milestone items fall back to field-level evidence when item evidence is missing" do
    field = contract_review_fields(:title_field)
    field.field_name = "lease_milestones"
    field.source_excerpt = "Tenant shall maintain insurance and renew coverage annually."
    field.source_locator = { "document_id" => "doc-1", "start_offset" => 12, "end_offset" => 86 }
    field.reasoning = "Insurance clause implies annual renewal."
    field.extracted_value = [
      { milestone_type: "insurance_renewal", due_date: "2025-08-01", description: "Renew policy", recurring: true, recurrence_interval: "annual" }
    ].to_json

    milestone = milestone_items(field).first

    assert_equal "broad", milestone_evidence_status(milestone)
    assert_equal field.source_excerpt, milestone_source_excerpt(milestone)
    assert_equal "doc-1", milestone_source_locator(milestone)["document_id"]
    assert_includes milestone_evidence_message(milestone), "broader milestone evidence"
  end

  test "milestone evidence status is unresolved without any source excerpt" do
    field = contract_review_fields(:title_field)
    field.field_name = "lease_milestones"
    field.source_excerpt = nil
    field.reasoning = nil
    field.extracted_value = [
      { milestone_type: "custom", due_date: "2025-05-01", description: "Unknown item", recurring: false }
    ].to_json

    milestone = milestone_items(field).first

    assert_equal "unresolved", milestone_evidence_status(milestone)
    assert_includes milestone_evidence_message(milestone), "could not point to a supporting excerpt"
  end

  test "key clause summary and purpose are human friendly" do
    key_clause = {
      "clause_type" => "sla",
      "content" => "Vendor must maintain 99.9% uptime for production services.",
      "confidence_score" => 91
    }

    assert_includes key_clause_summary(key_clause), "SLA"
    assert_includes key_clause_purpose_text(key_clause), "service levels"
    assert_equal "91%", key_clause_confidence_label(key_clause)
  end

  test "key clause items fall back to field-level evidence when item evidence is missing" do
    field = contract_review_fields(:title_field)
    field.field_name = "key_clauses"
    field.source_excerpt = "Either party may terminate with 30 days written notice."
    field.source_locator = { "document_id" => "doc-7", "start_offset" => 5, "end_offset" => 62 }
    field.reasoning = "Termination rights are explicit."
    field.extracted_value = [
      { clause_type: "termination", content: "Either party may terminate with 30 days written notice." }
    ].to_json

    key_clause = key_clause_items(field).first

    assert_equal "broad", key_clause_evidence_status(key_clause)
    assert_equal field.source_excerpt, key_clause_source_excerpt(key_clause)
    assert_equal "doc-7", key_clause_source_locator(key_clause)["document_id"]
    assert_includes key_clause_evidence_message(key_clause), "supporting clause language"
  end
end
