require "test_helper"

class ReviewMilestoneEvidenceBuilderTest < ActiveSupport::TestCase
  test "grounds milestone evidence from item-level excerpt when locator matches" do
    locator_service = ReviewSourceLocatorService.new([
      { id: "doc-1", name: "lease.txt", text: "Tenant must renew insurance coverage annually by August 1, 2025." }
    ])

    builder = ReviewMilestoneEvidenceBuilder.new(
      locator_service: locator_service,
      metadata: { "source_excerpt" => "Broad fallback excerpt", "reasoning" => "Array-level reasoning" }
    )

    milestones = builder.call([
      {
        "milestone_type" => "insurance_renewal",
        "due_date" => "2025-08-01",
        "description" => "Renew coverage",
        "source_excerpt" => "renew insurance coverage annually",
        "reasoning" => "Insurance terms are explicit."
      }
    ])

    first = milestones.first
    assert_equal "grounded", first["evidence_status"]
    assert first["source_excerpt"].present?
    assert_equal "doc-1", first.dig("source_locator", "document_id")
    assert_equal "Insurance terms are explicit.", first["reasoning"]
  end

  test "uses broad fallback evidence when per-item evidence cannot be resolved" do
    builder = ReviewMilestoneEvidenceBuilder.new(
      locator_service: nil,
      metadata: { "source_excerpt" => "Milestone obligations section", "reasoning" => "Found in milestone schedule." }
    )

    milestones = builder.call([
      {
        "milestone_type" => "custom",
        "due_date" => "2025-05-01",
        "description" => "Deliver report"
      }
    ])

    first = milestones.first
    assert_equal "broad", first["evidence_status"]
    assert_equal "Milestone obligations section", first["source_excerpt"]
    assert_equal "Found in milestone schedule.", first["reasoning"]
  end

  test "marks milestone unresolved when no evidence exists" do
    builder = ReviewMilestoneEvidenceBuilder.new(locator_service: nil, metadata: {})

    milestones = builder.call([
      {
        "milestone_type" => "custom",
        "due_date" => "2025-05-01",
        "description" => "Deliver report"
      }
    ])

    first = milestones.first
    assert_equal "unresolved", first["evidence_status"]
    assert_nil first["source_excerpt"]
  end
end
