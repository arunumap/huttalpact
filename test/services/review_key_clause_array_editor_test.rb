require "test_helper"

class ReviewKeyClauseArrayEditorTest < ActiveSupport::TestCase
  test "update edits clause fields and preserves evidence metadata" do
    raw_value = [
      {
        "clause_type" => "termination",
        "content" => "Either party may terminate with 30 days notice.",
        "page_reference" => "Section 9",
        "confidence_score" => 72,
        "source_document" => "master_service_agreement.pdf",
        "source_excerpt" => "Either party may terminate with 30 days notice.",
        "source_locator" => { "document_id" => "doc-1", "start_offset" => 10, "end_offset" => 54 },
        "source_match_strategy" => "exact",
        "reasoning" => "Termination language is explicit.",
        "evidence_status" => "grounded"
      }
    ].to_json

    editor = ReviewKeyClauseArrayEditor.new(raw_value)
    updated = editor.update(
      index: 0,
      attrs: {
        clause_type: "renewal",
        content: "Agreement renews for one additional year unless either party opts out.",
        page_reference: "Section 10",
        confidence_score: "88"
      }
    )

    assert_equal 1, updated.length
    assert_equal "renewal", updated.first["clause_type"]
    assert_equal "Agreement renews for one additional year unless either party opts out.", updated.first["content"]
    assert_equal "Section 10", updated.first["page_reference"]
    assert_equal 88, updated.first["confidence_score"]
    assert_equal "doc-1", updated.first["source_locator"]["document_id"]
    assert_equal "grounded", updated.first["evidence_status"]
  end

  test "remove deletes a single key clause entry" do
    raw_value = [
      { "clause_type" => "termination", "content" => "30 day notice" },
      { "clause_type" => "renewal", "content" => "Automatic annual renewal" }
    ].to_json

    editor = ReviewKeyClauseArrayEditor.new(raw_value)
    updated = editor.remove(index: 0)

    assert_equal 1, updated.length
    assert_equal "renewal", updated.first["clause_type"]
  end

  test "update raises for invalid clause type" do
    raw_value = [
      { "clause_type" => "termination", "content" => "30 day notice" }
    ].to_json

    editor = ReviewKeyClauseArrayEditor.new(raw_value)

    error = assert_raises(ReviewKeyClauseArrayEditor::InvalidKeyClausesError) do
      editor.update(index: 0, attrs: { clause_type: "invalid_type", content: "Updated content" })
    end

    assert_match(/Clause type is invalid/i, error.message)
  end

  test "remove raises when index is out of bounds" do
    raw_value = [
      { "clause_type" => "termination", "content" => "30 day notice" }
    ].to_json

    editor = ReviewKeyClauseArrayEditor.new(raw_value)

    error = assert_raises(ReviewKeyClauseArrayEditor::InvalidKeyClauseIndexError) do
      editor.remove(index: 2)
    end

    assert_match(/Key clause could not be found/i, error.message)
  end
end
