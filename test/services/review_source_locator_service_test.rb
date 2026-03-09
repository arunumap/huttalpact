require "test_helper"

class ReviewSourceLocatorServiceTest < ActiveSupport::TestCase
  setup do
    @documents = [
      {
        id: "doc-1",
        name: "contract.pdf",
        text: "This is the HVAC Maintenance Agreement between Acme Properties and CoolAir Services.\n\n" \
              "Article I: Term\n" \
              "The term begins January 1, 2025 and ends December 31, 2026.\n\n" \
              "Article II: Payment\n" \
              "Monthly fee: $1,200.00. Auto-renews annually unless 30 days written notice."
      }
    ]
    @service = ReviewSourceLocatorService.new(@documents)
  end

  # --- Exact match ---

  test "exact match returns locator with strategy exact when excerpt is verbatim" do
    result = @service.resolve("Monthly fee: $1,200.00.")

    assert_equal "exact", result[:strategy]
    assert_equal "doc-1", result[:locator]["document_id"]
    assert result[:locator]["start_offset"].present?
    assert result[:locator]["end_offset"].present?
    assert_includes result[:locator]["matched_text"], "Monthly fee"
  end

  # --- Normalized exact match ---

  test "normalized exact match finds excerpt that differs only in whitespace" do
    # The original has single spaces; our excerpt has extra whitespace
    result = @service.resolve("Monthly  fee:   $1,200.00.")

    assert_equal "exact", result[:strategy]
    assert_equal "doc-1", result[:locator]["document_id"]
    assert_includes result[:locator]["matched_text"], "Monthly fee"
  end

  test "normalized exact match is case insensitive" do
    result = @service.resolve("MONTHLY FEE: $1,200.00.")

    assert_equal "exact", result[:strategy]
    assert_equal "doc-1", result[:locator]["document_id"]
  end

  # --- Fuzzy match ---

  test "fuzzy match returns locator when excerpt has 70%+ token overlap" do
    documents = [
      {
        id: "doc-fuzzy",
        name: "test.pdf",
        text: "the quick brown fox jumps over the lazy dog in the park"
      }
    ]
    service = ReviewSourceLocatorService.new(documents)

    # 6 out of 8 unique tokens match the first 8-token window → 75% overlap
    result = service.resolve("the quick brown cat jumps over the lazy")

    assert_equal "fuzzy", result[:strategy]
    assert_equal "doc-fuzzy", result[:locator]["document_id"]
    assert result[:locator]["start_offset"] >= 0
    assert result[:locator]["end_offset"] > result[:locator]["start_offset"]
  end

  test "fuzzy match returns none when excerpt is too short" do
    result = @service.resolve("two words")

    # Only 2 tokens; fuzzy requires >= 3
    assert_equal "none", result[:strategy]
    assert_nil result[:locator]
  end

  # --- No match ---

  test "no match returns strategy none with nil locator" do
    result = @service.resolve("completely unrelated text about quantum physics and space travel")

    assert_equal "none", result[:strategy]
    assert_nil result[:locator]
  end

  # --- Anchor match ---

  test "anchor match returns locator when section_hint matches a heading" do
    result = @service.resolve(
      "something not in the text at all",
      section_hint: "Article II: Payment"
    )

    assert_equal "anchor", result[:strategy]
    assert_equal "doc-1", result[:locator]["document_id"]
    assert_includes result[:locator]["matched_text"], "Article II: Payment"
  end

  test "anchor match returns none when section_hint does not match" do
    result = @service.resolve(
      "something not in the text at all",
      section_hint: "Article XLIX: Nonexistent"
    )

    assert_equal "none", result[:strategy]
    assert_nil result[:locator]
  end

  # --- Blank excerpt ---

  test "blank excerpt returns strategy none" do
    assert_equal({ locator: nil, strategy: "none" }, @service.resolve(""))
    assert_equal({ locator: nil, strategy: "none" }, @service.resolve(nil))
    assert_equal({ locator: nil, strategy: "none" }, @service.resolve("   "))
  end

  # --- resolve_all ---

  test "resolve_all batch resolves fields and skips already resolved" do
    review = contract_reviews(:pending_review)

    unresolved = contract_review_fields(:title_field)
    unresolved.update_columns(
      source_excerpt: "HVAC Maintenance Agreement",
      source_locator: nil,
      source_match_strategy: nil
    )

    already_resolved = contract_review_fields(:monthly_value_field)
    already_resolved.update_columns(
      source_excerpt: "CoolAir Services",
      source_locator: { "document_id" => "doc-1", "start_offset" => 0, "end_offset" => 15, "matched_text" => "CoolAir Services" },
      source_match_strategy: "exact"
    )

    @service.resolve_all(review.fields)

    unresolved.reload
    assert_equal "exact", unresolved.source_match_strategy
    assert unresolved.source_locator.present?
    assert_equal "doc-1", unresolved.source_locator["document_id"]

    already_resolved.reload
    assert_equal 0, already_resolved.source_locator["start_offset"]
    assert_equal 15, already_resolved.source_locator["end_offset"]
  end

  test "resolve_all skips fields with blank source excerpt" do
    review = contract_reviews(:pending_review)

    field = contract_review_fields(:title_field)
    field.update_columns(source_excerpt: nil, source_locator: nil, source_match_strategy: nil)

    @service.resolve_all(review.fields)

    field.reload
    assert_nil field.source_locator
    assert_nil field.source_match_strategy
  end

  test "resolve_all uses section hints from existing locator metadata" do
    review = contract_reviews(:pending_review)
    field = contract_review_fields(:title_field)
    field.update_columns(
      source_excerpt: "text that does not exist in this document",
      source_locator: { "section_hint" => "Article II: Payment" },
      source_match_strategy: nil
    )

    @service.resolve_all(review.fields)

    field.reload
    assert_equal "anchor", field.source_match_strategy
    assert_equal "doc-1", field.source_locator["document_id"]
    assert_includes field.source_locator["matched_text"], "Article II: Payment"
  end

  # --- Multi-document ---

  test "multi document returns correct document_id when match is in second document" do
    documents = [
      { id: "doc-a", name: "main.pdf", text: "First document with generic contract terms." },
      { id: "doc-b", name: "amendment.pdf", text: "Amendment to HVAC Agreement. Updated pricing: $1,400.00 per month." }
    ]
    service = ReviewSourceLocatorService.new(documents)

    result = service.resolve("Updated pricing: $1,400.00 per month")

    assert_equal "exact", result[:strategy]
    assert_equal "doc-b", result[:locator]["document_id"]
    assert_includes result[:locator]["matched_text"], "Updated pricing"
  end

  # --- Offset accuracy ---

  test "exact match offsets correctly slice the original text" do
    result = @service.resolve("Article I: Term")

    assert_equal "exact", result[:strategy]
    locator = result[:locator]
    original_text = @documents.first[:text]

    sliced = original_text[locator["start_offset"]...locator["end_offset"]]
    assert_equal "Article I: Term", sliced
  end
end
