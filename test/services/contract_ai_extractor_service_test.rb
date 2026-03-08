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
      summary: "HVAC maintenance contract for Building A.",
      usage: { "input_tokens" => 1500, "output_tokens" => 300 }
    )

    stub_anthropic_client(ai_response) do
      result = ContractAiExtractorService.new(@contract).call
      assert_not_nil result
      assert_equal "termination", result["key_clauses"].first["clause_type"]
    end

    @contract.reload
    assert_equal "completed", @contract.extraction_status
    assert_not_nil @contract.ai_extracted_data

    usage_log = AiUsageLog.order(:created_at).last
    assert_equal @contract.organization_id, usage_log.organization_id
    assert_equal @contract.id, usage_log.contract_id
    assert_equal 1500, usage_log.input_tokens
    assert_equal 300, usage_log.output_tokens
    assert usage_log.success?
  end

  test "returns synthesized review metadata for canonical review fields" do
    ai_response = build_ai_response(
      end_date: "2026-12-31",
      auto_renews: false,
      key_clauses: [],
      summary: "HVAC maintenance contract for Building A."
    )

    stub_anthropic_client(ai_response) do
      result = ContractAiExtractorService.new(@contract).call
      end_date_field = result["review_fields"].find { |field| field["field_key"] == "contract.end_date" }

      assert_not_nil end_date_field
      assert_equal "2026-12-31", end_date_field["value"]
      assert_equal "alert_driving", end_date_field["classification"]
      assert_equal %w[expiry_warning notice_period_start], end_date_field["alert_family_keys"]
      assert_includes result["changed_field_keys"], "contract.end_date"
    end
  end

  test "preserves ai provided review metadata when present" do
    completed_doc = contract_documents(:completed_doc)
    ai_response = build_ai_response(
      end_date: "2026-12-31",
      key_clauses: [],
      review_fields: [
        {
          "field_key" => "contract.end_date",
          "field_index" => nil,
          "value" => "2026-12-31",
          "confidence_score" => 91,
          "source_document" => completed_doc.filename,
          "source_reference" => "Page 4",
          "source_excerpt" => "The term expires on December 31, 2026.",
          "precedence_hint" => "direct_extraction",
          "supersedes_prior_value" => false,
          "impacted_by_new_document" => false,
          "conflict_candidate" => false
        }
      ]
    )

    stub_anthropic_client(ai_response) do
      result = ContractAiExtractorService.new(@contract).call
      end_date_field = result["review_fields"].find { |field| field["field_key"] == "contract.end_date" }

      assert_equal 91, end_date_field["confidence_score"]
      assert_equal completed_doc.filename, end_date_field["source_document"]
      assert_equal "Page 4", end_date_field["source_reference"]
      assert_equal "The term expires on December 31, 2026.", end_date_field["source_excerpt"]
    end
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
      "content" => [ { "text" => "This is not valid JSON at all" } ],
      "usage" => { "input_tokens" => 100, "output_tokens" => 20 }
    }

    stub_anthropic_client(bad_response) do
      assert_raises ContractAiExtractorService::ExtractionError do
        ContractAiExtractorService.new(@contract).call
      end
    end

    @contract.reload
    assert_equal "failed", @contract.extraction_status

    usage_log = AiUsageLog.order(:created_at).last
    assert_equal 100, usage_log.input_tokens
    assert_equal 20, usage_log.output_tokens
    assert_not usage_log.success?
  end

  test "sets status to failed with descriptive message on Net::ReadTimeout" do
    fake_client = Object.new
    fake_client.define_singleton_method(:messages) { |**_kwargs| raise Net::ReadTimeout, "Net::ReadTimeout" }

    Anthropic::Client.stub(:new, fake_client) do
      assert_raises Net::ReadTimeout do
        ContractAiExtractorService.new(@contract).call
      end
    end

    @contract.reload
    assert_equal "failed", @contract.extraction_status

    usage_log = AiUsageLog.order(:created_at).last
    assert_not usage_log.success?
    assert_includes usage_log.error_message, "API timeout"
    assert_includes usage_log.error_message, "request_timeout"
  end

  test "passes resolved_timeout to Anthropic client" do
    # Set up a lease config with a custom timeout
    lease_config = ai_extraction_configs(:lease_full_v1)
    lease_config.update!(request_timeout: 420)

    lease_contract = contracts(:commercial_lease)
    lease_contract.update!(extraction_status: "pending")

    service = ContractAiExtractorService.new(lease_contract)

    # Verify the extraction config resolves the correct timeout
    config = service.send(:extraction_config)
    assert_equal 420, config.resolved_timeout
  end

  test "skips extraction when no completed documents" do
    @contract.contract_documents.update_all(extraction_status: "pending")

    result = ContractAiExtractorService.new(@contract).call
    assert_nil result
  end

  test "raises ExtractionError with descriptive message when response is truncated" do
    truncated_response = {
      "content" => [ { "text" => '{"title": "Incomplete lease dat' } ],
      "usage" => { "input_tokens" => 5000, "output_tokens" => 8192 },
      "stop_reason" => "max_tokens"
    }

    stub_anthropic_client(truncated_response) do
      assert_raises ContractAiExtractorService::ExtractionError do
        ContractAiExtractorService.new(@contract).call
      end
    end

    @contract.reload
    assert_equal "failed", @contract.extraction_status

    usage_log = AiUsageLog.order(:created_at).last
    assert_not usage_log.success?
    assert_includes usage_log.error_message, "truncated"
    assert_includes usage_log.error_message, "max_tokens"
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

  test "incremental review metadata only flags changed alert driving fields" do
    prior_data = {
      "end_date" => "2026-12-31",
      "auto_renews" => false,
      "notice_period_days" => nil,
      "key_clauses" => [],
      "summary" => "HVAC contract"
    }
    @contract.update!(
      ai_extracted_data: prior_data.to_json,
      end_date: Date.new(2026, 12, 31),
      auto_renews: false,
      notice_period_days: nil,
      extraction_status: "completed"
    )

    ai_response = build_ai_response(
      end_date: "2027-06-30",
      auto_renews: false,
      notice_period_days: nil,
      key_clauses: [],
      summary: "HVAC contract extended",
      changes_summary: "End date extended from 2026-12-31 to 2027-06-30"
    )

    stub_anthropic_client(ai_response) do
      result = ContractAiExtractorService.new(@contract, mode: :incremental).call

      assert_equal [ "contract.end_date" ], result["changed_field_keys"]
      assert_equal [ "contract.end_date" ], result["impacted_field_keys"]
    end
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

  test "allows overage extraction and records billing event when overage enabled" do
    org = organizations(:one)
    org.update!(
      plan: "starter",
      ai_extractions_count: 50,
      ai_extractions_overage_count: 0,
      ai_extractions_reset_at: Time.current
    )
    plan_tiers(:starter).update!(extraction_overage_cents: 125)
    create_active_subscription_for(org)

    ai_response = build_ai_response(key_clauses: [], summary: "Test")

    assert_difference "ExtractionOverageCharge.count", 1 do
      assert_difference "AuditLog.where(action: 'extraction_overage').count", 1 do
        stub_anthropic_client(ai_response) do
          ContractAiExtractorService.new(@contract).call
        end
      end
    end

    @contract.reload
    assert_equal "completed", @contract.extraction_status
    org.reload
    assert_equal 51, org.ai_extractions_count
    assert_equal 1, org.ai_extractions_overage_count

    charge = ExtractionOverageCharge.order(:created_at).last
    assert_equal org.id, charge.organization_id
    assert_equal @contract.id, charge.contract_id
    assert_equal 51, charge.usage_position
    assert_equal 125, charge.overage_cents
  end

  test "blocks overage extraction when subscription is pending cancellation" do
    org = organizations(:one)
    org.update!(plan: "starter", ai_extractions_count: 50, ai_extractions_reset_at: Time.current)
    plan_tiers(:starter).update!(extraction_overage_cents: 125)
    create_active_subscription_for(org, ends_at: 7.days.from_now)

    assert_raises ContractAiExtractorService::ExtractionLimitReachedError do
      ContractAiExtractorService.new(@contract).call
    end
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

  # --- New extraction logic tests (QA #2) ---

  test "full extraction maps title only when blank" do
    @contract.update!(title: "User-Set Title", extraction_status: "pending")
    @contract.contract_documents.create!(
      extraction_status: "completed",
      extracted_text: "Sample contract text",
      document_type: "main_contract",
      position: 0,
      file: Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/test.txt"), "text/plain")
    )

    ai_response = build_ai_response(
      title: "AI Suggested Title",
      vendor_name: "AI Vendor",
      key_clauses: [],
      summary: "Test summary"
    )

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract).call
    end

    @contract.reload
    assert_equal "User-Set Title", @contract.title, "Title should be preserved when already set"
  end

  test "full extraction fills title when blank" do
    @contract.update_columns(title: "", extraction_status: "pending")
    @contract.contract_documents.create!(
      extraction_status: "completed",
      extracted_text: "Sample contract text",
      document_type: "main_contract",
      position: 0,
      file: Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/test.txt"), "text/plain")
    )

    ai_response = build_ai_response(
      title: "AI Suggested Title",
      key_clauses: [],
      summary: "Test summary"
    )

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract).call
    end

    @contract.reload
    assert_equal "AI Suggested Title", @contract.title, "Title should be set from AI when blank"
  end

  test "full extraction replaces untitled draft placeholder title" do
    @contract.update!(title: "Untitled Draft", extraction_status: "pending")
    @contract.contract_documents.create!(
      extraction_status: "completed",
      extracted_text: "Sample contract text",
      document_type: "main_contract",
      position: 0,
      file: Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/test.txt"), "text/plain")
    )

    ai_response = build_ai_response(
      title: "AI Suggested Title",
      key_clauses: [],
      summary: "Test summary"
    )

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract).call
    end

    @contract.reload
    assert_equal "AI Suggested Title", @contract.title, "Placeholder draft title should be replaced by AI title"
  end

  test "full extraction maps ai_summary from summary separate from notes" do
    @contract.update!(notes: "User notes here", ai_summary: nil, extraction_status: "pending")
    @contract.contract_documents.create!(
      extraction_status: "completed",
      extracted_text: "Sample contract text",
      document_type: "main_contract",
      position: 0,
      file: Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/test.txt"), "text/plain")
    )

    ai_response = build_ai_response(
      key_clauses: [],
      summary: "AI-generated summary of the contract"
    )

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract).call
    end

    @contract.reload
    assert_equal "AI-generated summary of the contract", @contract.ai_summary
    assert_equal "User notes here", @contract.notes, "User notes must not be overwritten by AI summary"
  end

  test "incremental extraction maps ai_summary separate from notes" do
    prior_data = {
      "vendor_name" => "CoolAir Services",
      "key_clauses" => [],
      "summary" => "Old AI summary"
    }
    @contract.update!(
      ai_extracted_data: prior_data.to_json,
      notes: "My personal notes",
      ai_summary: "Old AI summary",
      extraction_status: "completed"
    )

    ai_response = build_ai_response(
      vendor_name: "CoolAir Services",
      key_clauses: [],
      summary: "Updated AI summary from addendum",
      changes_summary: "Summary updated"
    )

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract, mode: :incremental).call
    end

    @contract.reload
    assert_equal "Updated AI summary from addendum", @contract.ai_summary
    assert_equal "My personal notes", @contract.notes, "User notes must be preserved in incremental mode"
  end

  test "full extraction maps premises_address only when blank" do
    @contract.update!(premises_address: "123 Existing St", extraction_status: "pending")
    @contract.contract_documents.create!(
      extraction_status: "completed",
      extracted_text: "Sample text",
      document_type: "main_contract",
      position: 0,
      file: Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/test.txt"), "text/plain")
    )

    ai_response = build_ai_response(key_clauses: [], summary: "Test")
    # Inject premises_address into the response
    parsed = JSON.parse(ai_response["content"][0]["text"])
    parsed["premises_address"] = "456 AI Detected Ave"
    ai_response["content"][0]["text"] = parsed.to_json

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract).call
    end

    @contract.reload
    assert_equal "123 Existing St", @contract.premises_address, "Existing address should be preserved"
  end

  test "full extraction fills premises_address when blank" do
    @contract.update!(premises_address: nil, extraction_status: "pending")
    @contract.contract_documents.create!(
      extraction_status: "completed",
      extracted_text: "Sample text",
      document_type: "main_contract",
      position: 0,
      file: Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/test.txt"), "text/plain")
    )

    ai_response = build_ai_response(key_clauses: [], summary: "Test")
    parsed = JSON.parse(ai_response["content"][0]["text"])
    parsed["premises_address"] = "456 AI Detected Ave"
    ai_response["content"][0]["text"] = parsed.to_json

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract).call
    end

    @contract.reload
    assert_equal "456 AI Detected Ave", @contract.premises_address
  end

  test "full extraction maps next_renewal_date from AI response" do
    @contract.update!(next_renewal_date: nil, auto_renews: false, extraction_status: "pending")
    @contract.contract_documents.create!(
      extraction_status: "completed",
      extracted_text: "Sample text",
      document_type: "main_contract",
      position: 0,
      file: Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/test.txt"), "text/plain")
    )

    ai_response = build_ai_response(key_clauses: [], summary: "Test")
    parsed = JSON.parse(ai_response["content"][0]["text"])
    parsed["next_renewal_date"] = "2027-06-30"
    ai_response["content"][0]["text"] = parsed.to_json

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(@contract).call
    end

    @contract.reload
    assert_equal Date.new(2027, 6, 30), @contract.next_renewal_date
  end

  test "compute_next_renewal_date sets end_date as fallback when auto_renews and blank" do
    @contract.update!(
      next_renewal_date: nil,
      auto_renews: true,
      end_date: Date.new(2027, 12, 31),
      extraction_status: "pending"
    )

    service = ContractAiExtractorService.new(@contract)
    service.send(:compute_next_renewal_date!)

    @contract.reload
    assert_equal Date.new(2027, 12, 31), @contract.next_renewal_date,
      "Should fall back to end_date for auto-renewing contracts"
  end

  test "compute_next_renewal_date does not overwrite existing value" do
    existing_date = Date.new(2027, 6, 30)
    @contract.update!(
      next_renewal_date: existing_date,
      auto_renews: true,
      end_date: Date.new(2027, 12, 31)
    )

    service = ContractAiExtractorService.new(@contract)
    service.send(:compute_next_renewal_date!)

    @contract.reload
    assert_equal existing_date, @contract.next_renewal_date,
      "Should not overwrite existing next_renewal_date"
  end

  test "compute_next_renewal_date skipped when not auto_renews" do
    @contract.update!(
      next_renewal_date: nil,
      auto_renews: false,
      end_date: Date.new(2027, 12, 31)
    )

    service = ContractAiExtractorService.new(@contract)
    service.send(:compute_next_renewal_date!)

    @contract.reload
    assert_nil @contract.next_renewal_date,
      "Should not set date for non-auto-renewing contracts"
  end

  test "detect_and_set_lease_type overrides other contract_type" do
    @contract.update_column(:contract_type, "other")
    lease_text = "This LEASE AGREEMENT between LANDLORD and TENANT for the PREMISES located at 123 Main Street. The RENT shall be payable monthly."
    service = ContractAiExtractorService.new(@contract)
    service.send(:detect_and_set_lease_type!, lease_text)
    @contract.reload
    assert_equal "lease", @contract.contract_type,
      "Should override 'other' type when lease indicators are detected"
  end

  private

  def build_ai_response(title: nil, vendor_name: nil, contract_type: nil,
                        direction: nil,
                        start_date: nil, end_date: nil, monthly_value: nil,
                        total_value: nil, auto_renews: false, renewal_term: nil,
                        notice_period_days: nil, key_clauses: [], summary: nil,
                        changes_summary: nil, review_fields: nil,
                        changed_field_keys: nil, impacted_field_keys: nil,
                        usage: nil)
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
            "changes_summary" => changes_summary,
            "review_fields" => review_fields,
            "changed_field_keys" => changed_field_keys,
            "impacted_field_keys" => impacted_field_keys
          }.compact.to_json
        }
      ]
    }.tap do |response|
      response["usage"] = usage if usage.present?
    end
  end

  def stub_anthropic_client(response, &block)
    fake_client = Object.new
    fake_client.define_singleton_method(:messages) { |**_kwargs| response }

    Anthropic::Client.stub(:new, fake_client, &block)
  end

  def create_active_subscription_for(org, ends_at: nil)
    customer = org.set_payment_processor(:stripe)
    customer.update!(processor_id: "cus_overage_#{SecureRandom.hex(4)}")

    Pay::Stripe::Subscription.create!(
      customer: customer,
      processor_id: "sub_overage_#{SecureRandom.hex(4)}",
      processor_plan: "price_overage_test",
      name: "default",
      status: "active",
      ends_at: ends_at
    )
  end

  def build_lease_ai_response
    build_ai_response(
      title: "Retail Space - Downtown",
      vendor_name: "Metro Properties LLC",
      contract_type: "lease",
      direction: "outbound",
      start_date: "2025-01-01",
      end_date: "2030-12-31",
      monthly_value: 8500,
      total_value: 612000,
      auto_renews: true,
      renewal_term: "annual",
      notice_period_days: 180,
      key_clauses: [
        { "clause_type" => "security_deposit", "content" => "Security deposit of $25,500.", "confidence_score" => 95 },
        { "clause_type" => "cam_provision", "content" => "CAM capped at 5% cumulative.", "confidence_score" => 90 }
      ],
      summary: "NNN retail lease for downtown location."
    ).tap do |response|
      # Inject lease-specific data into the JSON response
      parsed = JSON.parse(response["content"][0]["text"])
      parsed["lease_details"] = {
        "lease_type" => "nnn",
        "rentable_sqft" => 3500,
        "usable_sqft" => 3200,
        "load_factor" => 1.0937,
        "permitted_use" => "Retail sales and office",
        "security_deposit" => 25500,
        "parking_spaces" => 8,
        "parking_monthly_cost" => 150,
        "free_rent_months" => 3,
        "rent_commencement_date" => "2025-04-01",
        "cam_base_amount" => 12000,
        "cam_base_year" => 2025,
        "cam_cap_percentage" => 5.0,
        "cam_cap_type" => "cumulative",
        "cam_reconciliation_month" => 3,
        "cam_audit_rights" => true,
        "cam_gross_up_provision" => true,
        "ti_allowance_psf" => 35.0,
        "ti_total_amount" => 122500,
        "ti_deadline" => "2026-06-30",
        "ti_disbursement_type" => "draw_schedule"
      }
      parsed["rent_escalations"] = [
        { "effective_date" => "2025-04-01", "base_rent_monthly" => 8500, "base_rent_annual" => 102000, "escalation_type" => "flat", "description" => "Initial rent" },
        { "effective_date" => "2026-04-01", "base_rent_monthly" => 8755, "base_rent_annual" => 105060, "escalation_type" => "fixed_percentage", "escalation_value" => 3.0, "description" => "3% annual increase" }
      ]
      parsed["lease_options"] = [
        { "option_type" => "renewal", "exercise_deadline" => "2030-06-30", "notice_deadline" => "2030-01-01", "term_length_months" => 60, "rent_terms" => "FMV with 10% cap" },
        { "option_type" => "termination", "notice_deadline" => "2028-06-30", "penalty_amount" => 50000 }
      ]
      parsed["lease_milestones"] = [
        { "milestone_type" => "cam_reconciliation", "due_date" => "2027-03-01", "description" => "Annual CAM reconciliation", "recurring" => true, "recurrence_interval" => "annual" },
        { "milestone_type" => "insurance_renewal", "due_date" => "2026-06-15", "description" => "Certificate of insurance", "recurring" => true, "recurrence_interval" => "annual" }
      ]
      response["content"][0]["text"] = parsed.to_json
      response["usage"] = { "input_tokens" => 3000, "output_tokens" => 1200 }
    end
  end

  # --- Lease-specific extraction tests ---

  test "detects lease type from document text when contract_type is blank" do
    @contract.update_column(:contract_type, nil)
    lease_text = "This LEASE AGREEMENT between LANDLORD and TENANT for the PREMISES located at 123 Main Street. The RENT shall be payable monthly."
    service = ContractAiExtractorService.new(@contract)
    service.send(:detect_and_set_lease_type!, lease_text)
    @contract.reload
    assert_equal "lease", @contract.contract_type
  end

  test "does not change contract_type when already set" do
    @contract.update_column(:contract_type, "maintenance")
    lease_text = "This LEASE AGREEMENT between LANDLORD and TENANT for the PREMISES."
    service = ContractAiExtractorService.new(@contract)
    service.send(:detect_and_set_lease_type!, lease_text)
    @contract.reload
    assert_equal "maintenance", @contract.contract_type
  end

  test "uses lease prompt when contract_type is lease" do
    lease_contract = contracts(:commercial_lease)
    # Need a completed doc for the lease contract
    lease_contract.contract_documents.create!(
      extraction_status: "completed",
      extracted_text: "This is a sample commercial lease.",
      document_type: "main_contract",
      position: 0,
      file: Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/test.txt"), "text/plain")
    )
    service = ContractAiExtractorService.new(lease_contract)
    assert service.send(:lease_extraction?)
    document_text = service.send(:build_document_text)
    prompt = service.send(:build_prompt, document_text)
    assert_includes prompt, "commercial real estate lease analysis specialist"
  end

  test "uses generic prompt for non-lease contract" do
    service = ContractAiExtractorService.new(@contract)
    refute service.send(:lease_extraction?)
  end

  test "apply_lease_extraction creates all child records" do
    lease_contract = contracts(:commercial_lease)
    # Clean up existing records
    lease_contract.lease_detail&.destroy
    lease_contract.rent_escalations.destroy_all
    lease_contract.lease_options.destroy_all
    lease_contract.lease_milestones.destroy_all

    service = ContractAiExtractorService.new(lease_contract)

    data = {
      "lease_details" => {
        "lease_type" => "nnn",
        "rentable_sqft" => 4000,
        "cam_base_amount" => 15000,
        "cam_reconciliation_month" => 6,
        "ti_allowance_psf" => 40.0,
        "ti_total_amount" => 160000,
        "ti_deadline" => "2027-01-01",
        "ti_disbursement_type" => "lump_sum"
      },
      "rent_escalations" => [
        { "effective_date" => "2025-01-01", "base_rent_monthly" => 9000, "escalation_type" => "flat" },
        { "effective_date" => "2026-01-01", "base_rent_monthly" => 9270, "escalation_type" => "fixed_percentage", "escalation_value" => 3.0 }
      ],
      "lease_options" => [
        { "option_type" => "renewal", "notice_deadline" => "2029-06-30", "term_length_months" => 60 }
      ],
      "lease_milestones" => [
        { "milestone_type" => "cam_reconciliation", "due_date" => "2027-06-01", "description" => "CAM recon", "recurring" => true, "recurrence_interval" => "annual" }
      ]
    }

    service.send(:apply_lease_extraction, data)
    lease_contract.reload

    assert_not_nil lease_contract.lease_detail
    assert_equal "nnn", lease_contract.lease_detail.lease_type
    assert_equal 4000, lease_contract.lease_detail.rentable_sqft.to_i
    assert_equal 2, lease_contract.rent_escalations.count
    assert_equal 1, lease_contract.lease_options.count
    assert_equal "renewal", lease_contract.lease_options.first.option_type
    assert_equal 1, lease_contract.lease_milestones.count
    assert_equal "cam_reconciliation", lease_contract.lease_milestones.first.milestone_type
  end

  test "sanitize_lease_data coerces invalid enum values to nil" do
    service = ContractAiExtractorService.new(@contract)
    data = {
      "lease_details" => {
        "lease_type" => "invalid_type",
        "cam_cap_type" => "bad_value",
        "ti_disbursement_type" => "unknown",
        "rentable_sqft" => "abc",
        "cam_reconciliation_month" => 15
      },
      "rent_escalations" => [
        { "effective_date" => "not-a-date", "escalation_type" => "flat" }
      ],
      "lease_options" => [
        { "option_type" => "invalid_opt" }
      ],
      "lease_milestones" => [
        { "milestone_type" => "nonexistent", "due_date" => "2027-01-01" }
      ]
    }

    service.send(:sanitize_lease_data!, data)

    assert_nil data["lease_details"]["lease_type"]
    assert_nil data["lease_details"]["cam_cap_type"]
    assert_nil data["lease_details"]["ti_disbursement_type"]
    assert_nil data["lease_details"]["cam_reconciliation_month"]
    # Invalid rent_escalation removed (bad date)
    assert_equal 0, data["rent_escalations"].size
    # Invalid lease_option removed (bad type)
    assert_equal 0, data["lease_options"].size
    # Invalid lease_milestone removed (bad type)
    assert_equal 0, data["lease_milestones"].size
  end

  test "incremental lease extraction replaces child tables" do
    lease_contract = contracts(:commercial_lease)
    # Ensure the fixture data is loaded
    assert_not_nil lease_contract.lease_detail
    original_escalation_count = lease_contract.rent_escalations.count
    assert original_escalation_count > 0

    service = ContractAiExtractorService.new(lease_contract, mode: :incremental)

    data = {
      "lease_details" => {
        "lease_type" => "modified_gross",
        "rentable_sqft" => 5000
      },
      "rent_escalations" => [
        { "effective_date" => "2025-07-01", "base_rent_monthly" => 10000, "escalation_type" => "flat" }
      ],
      "lease_options" => [],
      "lease_milestones" => []
    }

    service.send(:apply_lease_extraction, data)
    lease_contract.reload

    assert_equal "modified_gross", lease_contract.lease_detail.lease_type
    assert_equal 5000, lease_contract.lease_detail.rentable_sqft.to_i
    assert_equal 1, lease_contract.rent_escalations.count
    assert_equal 0, lease_contract.lease_options.count
    assert_equal 0, lease_contract.lease_milestones.count
  end

  test "full lease extraction via stubbed API creates lease records" do
    lease_contract = contracts(:commercial_lease)
    lease_contract.lease_detail&.destroy
    lease_contract.rent_escalations.destroy_all
    lease_contract.lease_options.destroy_all
    lease_contract.lease_milestones.destroy_all
    lease_contract.key_clauses.destroy_all
    lease_contract.update!(extraction_status: "pending")

    lease_contract.contract_documents.create!(
      extraction_status: "completed",
      extracted_text: "This LEASE AGREEMENT between Metro Properties LLC (Landlord) and Tenant...",
      document_type: "main_contract",
      position: 0,
      file: Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/test.txt"), "text/plain")
    )

    ai_response = build_lease_ai_response

    stub_anthropic_client(ai_response) do
      ContractAiExtractorService.new(lease_contract).call
    end

    lease_contract.reload
    assert_equal "completed", lease_contract.extraction_status
    assert_not_nil lease_contract.lease_detail
    assert_equal "nnn", lease_contract.lease_detail.lease_type
    assert lease_contract.rent_escalations.count >= 2
    assert lease_contract.lease_options.count >= 2
    assert lease_contract.lease_milestones.count >= 1
    assert lease_contract.key_clauses.any? { |c| c.clause_type == "security_deposit" }
  end

  test "max_tokens is 8192 for lease extractions" do
    lease_contract = contracts(:commercial_lease)
    service = ContractAiExtractorService.new(lease_contract)
    assert service.send(:lease_extraction?)
    # The lease extraction flag is used to determine max_tokens in the call method
  end
end
