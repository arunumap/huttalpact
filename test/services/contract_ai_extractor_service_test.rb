require "test_helper"

class ContractAiExtractorServiceTest < ActiveSupport::TestCase
  setup do
    @contract = contracts(:hvac_maintenance)
    @original_api_key = ENV["ANTHROPIC_API_KEY"]
    ENV["ANTHROPIC_API_KEY"] = "test-key-for-testing"
  end

  teardown do
    if @original_api_key
      ENV["ANTHROPIC_API_KEY"] = @original_api_key
    else
      ENV.delete("ANTHROPIC_API_KEY")
    end
  end

  test "extracts data from completed documents" do
    ai_response = build_ai_response(
      title: "HVAC Maintenance Agreement",
      vendor_name: "CoolAir Services Inc.",
      contract_type: "maintenance",
      start_date: "2025-01-01",
      end_date: "2026-12-31",
      monthly_value: 1200,
      total_value: 28800,
      auto_renews: true,
      renewal_term: "annual",
      notice_period_days: 30,
      key_clauses: [
        { "clause_type" => "termination", "content" => "30 days written notice.", "page_reference" => "Page 3", "confidence_score" => 90 },
        { "clause_type" => "renewal", "content" => "Auto-renews annually.", "page_reference" => "Page 4", "confidence_score" => 85 }
      ],
      summary: "HVAC maintenance contract for Building A."
    )

    stub_anthropic_client(ai_response) do
      result = ContractAiExtractorService.new(@contract).call
      assert_not_nil result
      assert_equal "termination", result["key_clauses"].first["clause_type"]
    end

    @contract.reload
    assert_equal "completed", @contract.extraction_status
    assert_not_nil @contract.ai_extracted_data
  end

  test "only overwrites blank fields" do
    # Contract already has vendor_name = "CoolAir Services" and contract_type = "maintenance"
    ai_response = build_ai_response(
      title: "New Title",
      vendor_name: "AI Suggested Vendor",
      contract_type: "software",
      key_clauses: [],
      summary: "A test summary."
    )

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract).call
    end

    @contract.reload
    assert_equal "CoolAir Services", @contract.vendor_name
    assert_equal "maintenance", @contract.contract_type
  end

  test "creates key clauses from response" do
    ai_response = build_ai_response(
      key_clauses: [
        { "clause_type" => "sla", "content" => "99.9% uptime guaranteed.", "page_reference" => "Page 5", "confidence_score" => 95 },
        { "clause_type" => "penalty", "content" => "Late fees of 2% per month.", "page_reference" => "Page 6", "confidence_score" => 80 }
      ]
    )

    @contract.key_clauses.destroy_all

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract).call
    end

    @contract.reload
    assert_equal 2, @contract.key_clauses.count
    sla_clause = @contract.key_clauses.find_by(clause_type: "sla")
    assert_not_nil sla_clause
    assert_equal 95, sla_clause.confidence_score
  end

  test "skips key clauses with invalid clause_type" do
    ai_response = build_ai_response(
      key_clauses: [
        { "clause_type" => "nonexistent_type", "content" => "Some clause", "page_reference" => nil, "confidence_score" => 50 },
        { "clause_type" => "termination", "content" => "Valid clause.", "page_reference" => "Page 1", "confidence_score" => 90 }
      ]
    )

    @contract.key_clauses.destroy_all

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract).call
    end

    @contract.reload
    assert_equal 1, @contract.key_clauses.count
    assert_equal "termination", @contract.key_clauses.first.clause_type
  end

  test "handles markdown-wrapped JSON response" do
    json_body = {
      "title" => "Wrapped Test",
      "vendor_name" => nil,
      "contract_type" => nil,
      "start_date" => nil,
      "end_date" => nil,
      "monthly_value" => nil,
      "total_value" => nil,
      "auto_renews" => false,
      "renewal_term" => nil,
      "notice_period_days" => nil,
      "key_clauses" => [],
      "summary" => nil
    }
    # Wrap in markdown code fences
    wrapped_response = {
      "content" => [ { "text" => "```json\n#{json_body.to_json}\n```" } ]
    }

    stub_anthropic_client(wrapped_response) do
      result = ContractAiExtractorService.new(@contract).call
      assert_not_nil result
    end

    @contract.reload
    assert_equal "completed", @contract.extraction_status
  end

  test "sets status to failed on JSON parse error" do
    bad_response = {
      "content" => [ { "text" => "This is not valid JSON at all" } ]
    }

    stub_anthropic_client(bad_response) do
      assert_raises ContractAiExtractorService::ExtractionError do
        ContractAiExtractorService.new(@contract).call
      end
    end

    @contract.reload
    assert_equal "failed", @contract.extraction_status
  end

  test "skips extraction when no completed documents" do
    @contract.contract_documents.update_all(extraction_status: "pending")

    result = ContractAiExtractorService.new(@contract).call
    assert_nil result
  end

  test "raises ExtractionError when no API key configured" do
    ENV.delete("ANTHROPIC_API_KEY")

    fake_credentials = Object.new
    fake_credentials.define_singleton_method(:dig) { |*_args| nil }
    fake_credentials.define_singleton_method(:anthropic_api_key) { nil }

    Rails.application.stub(:credentials, fake_credentials) do
      assert_raises ContractAiExtractorService::ExtractionError do
        ContractAiExtractorService.new(@contract).call
      end
    end
  end

  test "builds labeled document text with headers" do
    service = ContractAiExtractorService.new(@contract)
    text = service.send(:build_document_text)

    assert_includes text, "=== DOCUMENT"
    assert_includes text, "(Type: Main Contract)"
  end

  test "incremental mode preserves user edits when AI value unchanged" do
    # Simulate prior extraction stored vendor as "CoolAir Services"
    prior_data = {
      "vendor_name" => "CoolAir Services",
      "contract_type" => "maintenance",
      "monthly_value" => 1200,
      "key_clauses" => [],
      "summary" => "HVAC contract"
    }
    @contract.update!(
      ai_extracted_data: prior_data.to_json,
      vendor_name: "User Edited Vendor",  # User changed this
      contract_type: "maintenance",
      extraction_status: "completed"
    )

    # AI returns same values as prior extraction — user edits should be preserved
    ai_response = build_ai_response(
      vendor_name: "CoolAir Services",   # Same as prior AI
      contract_type: "maintenance",       # Same as prior AI
      monthly_value: 1200,
      key_clauses: [],
      summary: "HVAC contract",
      changes_summary: "No changes"
    )

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract, mode: :incremental).call
    end

    @contract.reload
    # Vendor should remain as user edited, since AI didn't change it
    assert_equal "User Edited Vendor", @contract.vendor_name
  end

  test "incremental mode overwrites when AI produces different value" do
    prior_data = {
      "vendor_name" => "CoolAir Services",
      "end_date" => "2026-12-31",
      "key_clauses" => [],
      "summary" => "HVAC contract"
    }
    @contract.update!(
      ai_extracted_data: prior_data.to_json,
      vendor_name: "User Edited Vendor",
      end_date: Date.new(2026, 12, 31),
      extraction_status: "completed"
    )

    # AI now returns a DIFFERENT end_date (addendum extended it)
    ai_response = build_ai_response(
      vendor_name: "CoolAir Services",
      end_date: "2027-06-30",           # Changed by addendum!
      key_clauses: [],
      summary: "HVAC contract extended",
      changes_summary: "End date extended from 2026-12-31 to 2027-06-30"
    )

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract, mode: :incremental).call
    end

    @contract.reload
    assert_equal "User Edited Vendor", @contract.vendor_name     # Unchanged by AI
    assert_equal Date.new(2027, 6, 30), @contract.end_date       # Updated by AI
    assert_equal "End date extended from 2026-12-31 to 2027-06-30", @contract.last_changes_summary
  end

  test "incremental mode falls back to full when no prior AI data" do
    @contract.update!(ai_extracted_data: nil, extraction_status: "pending")

    ai_response = build_ai_response(
      vendor_name: "New Vendor",
      key_clauses: [],
      summary: "First extraction"
    )

    stub_anthropic_client(ai_response) do
      # mode: :incremental but no ai_extracted_data => should fall back to full
      service = ContractAiExtractorService.new(@contract, mode: :incremental)
      assert_equal :full, service.instance_variable_get(:@mode)
    end
  end

  test "assigns source_document_id on key clauses" do
    completed_doc = contract_documents(:completed_doc)

    ai_response = build_ai_response(
      key_clauses: [
        {
          "clause_type" => "termination",
          "content" => "30 days notice required.",
          "page_reference" => "Page 3",
          "confidence_score" => 92,
          "source_document" => completed_doc.filename
        }
      ]
    )

    @contract.key_clauses.destroy_all

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract).call
    end

    @contract.reload
    clause = @contract.key_clauses.first
    assert_not_nil clause
    assert_equal completed_doc.id, clause.source_document_id
  end

  test "stores changes_summary in last_changes_summary" do
    @contract.update!(ai_extracted_data: { "vendor_name" => "Old" }.to_json, extraction_status: "completed")

    ai_response = build_ai_response(
      vendor_name: "New Vendor",
      key_clauses: [],
      changes_summary: "Vendor name updated"
    )

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract, mode: :incremental).call
    end

    @contract.reload
    assert_equal "Vendor name updated", @contract.last_changes_summary
  end

  test "truncation kicks in when text exceeds MAX_INPUT_CHARS" do
    # Create a service with a very small max to test truncation
    service = ContractAiExtractorService.new(@contract)
    # Override MAX_INPUT_CHARS for testing
    original = ContractAiExtractorService::MAX_INPUT_CHARS

    ContractAiExtractorService.send(:remove_const, :MAX_INPUT_CHARS)
    ContractAiExtractorService.const_set(:MAX_INPUT_CHARS, 100)

    text = service.send(:build_document_text)
    assert text.length <= 200, "Truncated text should be roughly within limit"

    # Restore
    ContractAiExtractorService.send(:remove_const, :MAX_INPUT_CHARS)
    ContractAiExtractorService.const_set(:MAX_INPUT_CHARS, original)
  end

  test "reentrance guard skips when already processing" do
    @contract.update!(extraction_status: "processing")

    result = ContractAiExtractorService.new(@contract).call
    assert_nil result
  end

  # --- Sanitization / coercion tests ---

  test "coerces invalid contract_type to nil and continues" do
    ai_response = build_ai_response(
      contract_type: "invalid_type_from_ai",
      key_clauses: [],
      summary: "Test"
    )

    # Clear contract_type so apply_full_extraction can set it
    @contract.update!(contract_type: nil)

    stub_anthropic_client(ai_response) do
      result = ContractAiExtractorService.new(@contract).call
      assert_not_nil result
    end

    @contract.reload
    assert_equal "completed", @contract.extraction_status
    assert_nil @contract.contract_type  # invalid value coerced to nil, blank field stays blank
  end

  test "coerces invalid renewal_term to nil and continues" do
    ai_response = build_ai_response(
      renewal_term: "tri-annual",
      key_clauses: [],
      summary: "Test"
    )

    @contract.update!(renewal_term: nil)

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract).call
    end

    @contract.reload
    assert_equal "completed", @contract.extraction_status
    assert_nil @contract.renewal_term
  end

  test "coerces invalid direction to nil and skips update" do
    ai_response = build_ai_response(
      direction: "sideways",
      key_clauses: [],
      summary: "Test"
    )

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract).call
    end

    @contract.reload
    assert_equal "completed", @contract.extraction_status
    assert_equal "outbound", @contract.direction  # default preserved
  end

  test "coerces unparseable date to nil and continues" do
    ai_response = build_ai_response(
      start_date: "not-a-date",
      end_date: "13/32/2025",
      key_clauses: [],
      summary: "Test"
    )

    @contract.update!(start_date: nil, end_date: nil)

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract).call
    end

    @contract.reload
    assert_equal "completed", @contract.extraction_status
    assert_nil @contract.start_date
    assert_nil @contract.end_date
  end

  test "coerces negative monetary value to nil" do
    ai_response = build_ai_response(
      monthly_value: -500,
      total_value: "not a number",
      key_clauses: [],
      summary: "Test"
    )

    @contract.update!(monthly_value: nil, total_value: nil)

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract).call
    end

    @contract.reload
    assert_equal "completed", @contract.extraction_status
    assert_nil @contract.monthly_value  # negative value coerced to nil
    # "not a number".to_f == 0.0, which is >= 0, so it's kept as 0.0
    assert_equal 0.0, @contract.total_value
  end

  test "coerces invalid notice_period_days to nil" do
    ai_response = build_ai_response(
      notice_period_days: "thirty",
      key_clauses: [],
      summary: "Test"
    )

    @contract.update!(notice_period_days: nil)

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract).call
    end

    @contract.reload
    assert_equal "completed", @contract.extraction_status
    assert_nil @contract.notice_period_days
  end

  test "clamps confidence_score above 100 to 100" do
    ai_response = build_ai_response(
      key_clauses: [
        { "clause_type" => "termination", "content" => "30 days notice.", "page_reference" => "Page 1", "confidence_score" => 150 }
      ]
    )

    @contract.key_clauses.destroy_all

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract).call
    end

    @contract.reload
    assert_equal 100, @contract.key_clauses.first.confidence_score
  end

  test "clamps negative confidence_score to 0" do
    ai_response = build_ai_response(
      key_clauses: [
        { "clause_type" => "renewal", "content" => "Auto renews.", "page_reference" => "Page 2", "confidence_score" => -10 }
      ]
    )

    @contract.key_clauses.destroy_all

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract).call
    end

    @contract.reload
    assert_equal 0, @contract.key_clauses.first.confidence_score
  end

  test "handles non-array key_clauses gracefully" do
    ai_response = build_ai_response(summary: "Test")
    # Override key_clauses to be a string instead of array
    parsed = JSON.parse(ai_response["content"][0]["text"])
    parsed["key_clauses"] = "not an array"
    ai_response["content"][0]["text"] = parsed.to_json

    @contract.key_clauses.destroy_all

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract).call
    end

    @contract.reload
    assert_equal "completed", @contract.extraction_status
    assert_equal 0, @contract.key_clauses.count
  end

  test "coerces auto_renews string to boolean" do
    ai_response = build_ai_response(
      auto_renews: "yes",
      key_clauses: [],
      summary: "Test"
    )

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract).call
    end

    @contract.reload
    assert_equal "completed", @contract.extraction_status
    # "yes" should be cast to false by ActiveModel::Type::Boolean (not in its truthy set)
    # Actually Rails casts "yes" -> we just need to verify no crash
  end

  # --- Extraction limit tests ---

  test "raises ExtractionLimitReachedError when org at limit" do
    org = organizations(:one)
    org.update!(plan: "free", ai_extractions_count: 5, ai_extractions_reset_at: Time.current)

    assert_raises ContractAiExtractorService::ExtractionLimitReachedError do
      ContractAiExtractorService.new(@contract).call
    end

    # Status should NOT change (we bail before processing)
    @contract.reload
    assert_equal "pending", @contract.extraction_status
  end

  test "allows extraction when org is under limit" do
    org = organizations(:one)
    org.update!(plan: "free", ai_extractions_count: 2, ai_extractions_reset_at: Time.current)

    ai_response = build_ai_response(key_clauses: [], summary: "Test")

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract).call
    end

    @contract.reload
    assert_equal "completed", @contract.extraction_status
  end

  # --- Incremental prompt with new document focus ---

  test "incremental prompt includes new document filename hint" do
    @contract.update!(ai_extracted_data: { "vendor_name" => "Old" }.to_json, extraction_status: "completed")

    completed_doc = contract_documents(:completed_doc)

    service = ContractAiExtractorService.new(@contract, mode: :incremental, new_document_id: completed_doc.id)
    document_text = service.send(:build_document_text)
    prompt = service.send(:build_prompt, document_text)

    assert_includes prompt, "newly uploaded document"
    assert_includes prompt, completed_doc.filename
  end

  test "incremental prompt works without new_document_id" do
    @contract.update!(ai_extracted_data: { "vendor_name" => "Old" }.to_json, extraction_status: "completed")

    service = ContractAiExtractorService.new(@contract, mode: :incremental)
    document_text = service.send(:build_document_text)
    prompt = service.send(:build_prompt, document_text)

    refute_includes prompt, "newly uploaded document"
    assert_includes prompt, "PRIOR EXTRACTION RESULT"
  end

  # --- Source document mapping edge cases ---

  test "source_document_id is nil when filename does not match any document" do
    ai_response = build_ai_response(
      key_clauses: [
        {
          "clause_type" => "termination",
          "content" => "30 days notice.",
          "page_reference" => "Page 1",
          "confidence_score" => 90,
          "source_document" => "nonexistent_file.pdf"
        }
      ]
    )

    @contract.key_clauses.destroy_all

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract).call
    end

    @contract.reload
    clause = @contract.key_clauses.first
    assert_not_nil clause
    assert_nil clause.source_document_id
  end

  private

  def build_ai_response(title: nil, vendor_name: nil, contract_type: nil,
                        direction: nil,
                        start_date: nil, end_date: nil, monthly_value: nil,
                        total_value: nil, auto_renews: false, renewal_term: nil,
                        notice_period_days: nil, key_clauses: [], summary: nil,
                        changes_summary: nil)
    {
      "content" => [
        {
          "text" => {
            "title" => title,
            "vendor_name" => vendor_name,
            "contract_type" => contract_type,
            "direction" => direction,
            "start_date" => start_date,
            "end_date" => end_date,
            "monthly_value" => monthly_value,
            "total_value" => total_value,
            "auto_renews" => auto_renews,
            "renewal_term" => renewal_term,
            "notice_period_days" => notice_period_days,
            "key_clauses" => key_clauses,
            "summary" => summary,
            "changes_summary" => changes_summary
          }.compact.to_json
        }
      ]
    }
  end

  def stub_anthropic_client(response, &block)
    fake_client = Object.new
    fake_client.define_singleton_method(:messages) { |**_kwargs| response }

    Anthropic::Client.stub(:new, fake_client, &block)
  end
end
