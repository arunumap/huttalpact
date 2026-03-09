require "test_helper"

class ReviewKeyClauseEvidenceBuilderTest < ActiveSupport::TestCase
  test "builds grounded evidence when clause excerpt resolves to source text" do
    locator_service = ReviewSourceLocatorService.new(
      [ { id: "doc-1", name: "msa.pdf", text: "Either party may terminate with 30 days notice for convenience." } ]
    )

    builder = ReviewKeyClauseEvidenceBuilder.new(locator_service: locator_service, metadata: {})
    clauses = [
      {
        "clause_type" => "termination",
        "content" => "Either party may terminate with 30 days notice.",
        "source_excerpt" => "Either party may terminate with 30 days notice."
      }
    ]

    result = builder.call(clauses).first

    assert_equal "grounded", result["evidence_status"]
    assert result["source_excerpt"].present?
    assert_equal "doc-1", result["source_locator"]["document_id"]
    assert_includes %w[exact fuzzy], result["source_match_strategy"]
  end

  test "falls back to array-level metadata evidence as broad context" do
    locator_service = ReviewSourceLocatorService.new(
      [ { id: "doc-2", name: "msa.pdf", text: "Service levels and uptime commitments are defined in section 8." } ]
    )
    metadata = {
      "source_excerpt" => "Service levels and uptime commitments are defined in section 8.",
      "reasoning" => "Clause group appears in SLA section."
    }

    builder = ReviewKeyClauseEvidenceBuilder.new(locator_service: locator_service, metadata: metadata)
    clauses = [
      {
        "clause_type" => "sla",
        "content" => "Uptime target is 99.9%",
        "source_excerpt" => nil
      }
    ]

    result = builder.call(clauses).first

    assert_equal "broad", result["evidence_status"]
    assert_equal metadata["reasoning"], result["reasoning"]
    assert_equal "doc-2", result["source_locator"]["document_id"]
  end

  test "marks clause unresolved when evidence cannot be located" do
    locator_service = ReviewSourceLocatorService.new(
      [ { id: "doc-3", name: "msa.pdf", text: "General terms and conditions." } ]
    )

    builder = ReviewKeyClauseEvidenceBuilder.new(locator_service: locator_service, metadata: {})
    clauses = [
      {
        "clause_type" => "liability",
        "content" => "Liability cap equals twelve months of fees.",
        "source_excerpt" => "Liability cap equals twelve months of fees."
      }
    ]

    result = builder.call(clauses).first

    assert_equal "unresolved", result["evidence_status"]
    assert_nil result["source_locator"]
    assert_equal "Liability cap equals twelve months of fees.", result["source_excerpt"]
  end
end
