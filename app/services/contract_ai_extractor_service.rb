class ContractAiExtractorService
  class ExtractionError < StandardError; end

  # ~400k chars ≈ ~100k tokens, safely under Claude's 200k context window
  MAX_INPUT_CHARS = 400_000

  JSON_SCHEMA = <<~SCHEMA
    {
      "title": "A short descriptive title for this contract",
      "vendor_name": "The other party / vendor / landlord name",
      "contract_type": "One of: lease, service_agreement, maintenance, insurance, software, other",
      "direction": "inbound if the organization receiving this contract is being paid (revenue), outbound if the organization is paying (expense)",
      "start_date": "YYYY-MM-DD or null",
      "end_date": "YYYY-MM-DD or null",
      "monthly_value": numeric or null,
      "total_value": numeric or null,
      "auto_renews": true or false,
      "renewal_term": "month-to-month, annual, 2-year, or custom",
      "notice_period_days": numeric or null,
      "key_clauses": [
        {
          "clause_type": "One of: termination, renewal, penalty, sla, price_escalation, liability, insurance_requirement",
          "content": "The actual clause text or summary",
          "page_reference": "Page X or Section Y",
          "confidence_score": 0-100,
          "source_document": "The exact filename of the document this clause came from"
        }
      ],
      "summary": "2-3 sentence summary of the contract"
    }
  SCHEMA

  FULL_EXTRACTION_PROMPT = <<~PROMPT
    You are a contract analysis assistant. You will receive text from one or more contract documents.
    Each document is labeled with a header like:
      === DOCUMENT 1: "filename.pdf" (Type: Main Contract) ===

    Documents may include a main contract plus addendums, amendments, exhibits, or SOWs.
    When there are multiple documents:
    - Amendments and addendums OVERRIDE conflicting terms in the main contract.
    - Later documents take precedence over earlier ones for the same field.
    - Combine key clauses from ALL documents.

    Return ONLY valid JSON with these fields (no markdown, no explanation):
    #{JSON_SCHEMA}

    Be precise with dates and monetary values. If information is not found, use null.
    For direction: if the contract describes services/goods being provided TO the organization (they pay), use "outbound". If the organization is providing services/goods and will be paid, use "inbound". Default to "outbound" if unclear.
    For key clauses, include the most important ones that affect renewals, costs, and obligations.
    For source_document, use the EXACT filename from the document header.

    CONTRACT DOCUMENTS:
  PROMPT

  INCREMENTAL_EXTRACTION_PROMPT = <<~PROMPT
    You are a contract analysis assistant. A contract has already been analyzed and you are now given an additional document (addendum, amendment, exhibit, etc.) that was just uploaded.

    PRIOR EXTRACTION RESULT (JSON):
    %{prior_json}

    A new document has been added. Re-analyze the full contract considering this new document.
    The new document may override or supplement terms from the prior extraction.
    Amendments and addendums OVERRIDE conflicting terms in the main contract.

    Return ONLY valid JSON with these fields (no markdown, no explanation):
    #{JSON_SCHEMA}

    Also include an additional field:
      "changes_summary": "A brief human-readable summary of what changed compared to the prior extraction (e.g., 'End date extended from 2025-12-31 to 2026-06-30. Added SLA penalty clause.')"

    Be precise with dates and monetary values. If information is not found, use null.
    For direction: if the contract describes services/goods being provided TO the organization (they pay), use "outbound". If the organization is providing services/goods and will be paid, use "inbound". Default to "outbound" if unclear.
    For key clauses, return the COMPLETE updated set of clauses from ALL documents (not just the new one).
    For source_document, use the EXACT filename from the document header.

    CONTRACT DOCUMENTS:
  PROMPT

  # Raised when the organization has hit its monthly AI extraction limit
  class ExtractionLimitReachedError < StandardError; end

  def initialize(contract, mode: :full, new_document_id: nil)
    @contract = contract
    @new_document_id = new_document_id

    # Determine extraction mode; fall back to full if no prior data for incremental
    @mode = if mode == :incremental && @contract.ai_extracted_data.present?
              :incremental
    else
              :full
    end
  end

  def call
    # Enforce plan extraction limits before making an API call
    org = @contract.organization
    if org
      org.reset_monthly_extractions_if_needed!
      if org.at_extraction_limit?
        Rails.logger.info("AI extraction blocked for contract #{@contract.id}: org #{org.id} at extraction limit")
        raise ExtractionLimitReachedError, "Monthly AI extraction limit reached (#{org.plan_extraction_limit} for #{org.plan} plan)"
      end
    end

    document_text = build_document_text
    return if document_text.blank?

    # Atomic reentrance guard: only proceed if we can claim the "processing" status
    rows_updated = Contract.where(id: @contract.id)
      .where.not(extraction_status: "processing")
      .update_all(extraction_status: "processing")
    return if rows_updated == 0

    @contract.reload

    prompt = build_prompt(document_text)

    response = client.messages(
      parameters: {
        model: "claude-sonnet-4-20250514",
        max_tokens: 4096,
        messages: [ { role: "user", content: prompt } ]
      }
    )

    raw_text = response.dig("content", 0, "text")
    raise ExtractionError, "No content in AI response" if raw_text.blank?

    # Strip markdown code fences if present
    json_text = raw_text.gsub(/\A```(?:json)?\n?/, "").gsub(/\n?```\z/, "").strip
    extracted = JSON.parse(json_text)

    # Sanitize/coerce AI output before applying to models
    sanitize_extracted_data!(extracted)

    apply_extraction(extracted)

    update_attrs = {
      extraction_status: "completed",
      ai_extracted_data: extracted.except("changes_summary").to_json
    }
    update_attrs[:last_changes_summary] = extracted["changes_summary"] if extracted["changes_summary"].present?

    @contract.update!(update_attrs)

    # Track extraction usage against plan limits
    @contract.organization&.increment_extraction_count!

    extracted
  rescue JSON::ParserError => e
    @contract.update!(extraction_status: "failed")
    Rails.logger.error("AI extraction JSON parse error for contract #{@contract.id}: #{e.message}")
    raise ExtractionError, "Failed to parse AI response as JSON"
  rescue ExtractionLimitReachedError
    # Don't change extraction status — this is a billing limit, not an extraction failure
    raise
  rescue Faraday::ClientError => e
    @contract.update!(extraction_status: "failed")
    body = e.response&.dig(:body) rescue nil
    Rails.logger.error("AI extraction API error for contract #{@contract.id}: #{e.message} — #{body}")
    raise e
  rescue => e
    @contract.update!(extraction_status: "failed")
    Rails.logger.error("AI extraction failed for contract #{@contract.id}: #{e.message}")
    raise e
  end

  private

  def client
    @client ||= Anthropic::Client.new(access_token: api_key)
  end

  def api_key
    Rails.application.credentials.dig(:anthropic, :api_key) ||
      Rails.application.credentials.anthropic_api_key ||
      ENV["ANTHROPIC_API_KEY"] ||
      raise(ExtractionError, "Anthropic API key not configured")
  end

  # Build labeled, truncated text from all completed documents
  def build_document_text
    documents = @contract.contract_documents.completed.ordered.to_a
    return "" if documents.empty?

    sections = documents.each_with_index.map do |doc, idx|
      header = "=== DOCUMENT #{idx + 1}: \"#{doc.filename}\" (Type: #{doc.document_type_label}) ==="
      text = doc.extracted_text.to_s.strip
      "#{header}\n#{text}"
    end

    combined = sections.join("\n\n")

    if combined.length > MAX_INPUT_CHARS
      truncate_proportionally(sections)
    else
      combined
    end
  end

  # Truncate each document's text proportionally, keeping start and end
  def truncate_proportionally(sections)
    # Reserve space for headers and separators
    overhead = sections.sum { |s| s.lines.first.length + 20 }
    available = MAX_INPUT_CHARS - overhead
    return sections.first[0...MAX_INPUT_CHARS] if available <= 0

    total_text_length = sections.sum { |s| s.length }

    sections.map do |section|
      header = section.lines.first
      text = section.lines.drop(1).join

      # Each doc gets a proportional share of available chars
      share = (text.length.to_f / total_text_length * available).to_i
      if text.length <= share
        section
      else
        # Keep first 60% and last 40% of the share, with truncation notice
        keep_start = (share * 0.6).to_i
        keep_end = (share * 0.4).to_i
        truncated_chars = text.length - keep_start - keep_end
        "#{header}#{text[0...keep_start]}\n\n[... #{truncated_chars} characters truncated for length ...]\n\n#{text[-keep_end..]}"
      end
    end.join("\n\n")
  end

  def build_prompt(document_text)
    if @mode == :incremental
      prior_json = @contract.ai_extracted_data
      new_doc_hint = ""
      if @new_document_id
        new_doc = @contract.contract_documents.find_by(id: @new_document_id)
        if new_doc
          new_doc_hint = "\n\nThe newly uploaded document is: \"#{new_doc.filename}\" (Type: #{new_doc.document_type_label}). Pay special attention to how it modifies or supplements the existing contract terms.\n"
        end
      end
      format(INCREMENTAL_EXTRACTION_PROMPT, prior_json: prior_json) + new_doc_hint + "\n#{document_text}"
    else
      "#{FULL_EXTRACTION_PROMPT}\n#{document_text}"
    end
  end

  # Build a lookup from filename -> document id for assigning source_document_id
  def document_id_lookup
    @document_id_lookup ||= @contract.contract_documents.completed.each_with_object({}) do |doc, hash|
      hash[doc.filename] = doc.id
    end
  end

  # Sanitize and coerce AI-returned values so invalid enums/dates/numerics
  # are set to nil rather than causing validation failures.
  def sanitize_extracted_data!(data)
    # Coerce contract_type to a valid enum or nil
    if data["contract_type"].present? && !Contract::CONTRACT_TYPES.include?(data["contract_type"])
      Rails.logger.warn("AI returned invalid contract_type '#{data["contract_type"]}' for contract #{@contract.id}, setting to nil")
      data["contract_type"] = nil
    end

    # Coerce direction to a valid enum or nil
    if data["direction"].present? && !Contract::DIRECTIONS.include?(data["direction"])
      Rails.logger.warn("AI returned invalid direction '#{data["direction"]}' for contract #{@contract.id}, setting to nil")
      data["direction"] = nil
    end

    # Coerce renewal_term to a valid enum or nil
    if data["renewal_term"].present? && !Contract::RENEWAL_TERMS.include?(data["renewal_term"])
      Rails.logger.warn("AI returned invalid renewal_term '#{data["renewal_term"]}' for contract #{@contract.id}, setting to nil")
      data["renewal_term"] = nil
    end

    # Coerce dates — if unparseable, set to nil
    %w[start_date end_date].each do |field|
      next if data[field].nil?
      begin
        Date.parse(data[field].to_s)
      rescue Date::Error, ArgumentError
        Rails.logger.warn("AI returned invalid #{field} '#{data[field]}' for contract #{@contract.id}, setting to nil")
        data[field] = nil
      end
    end

    # Coerce numeric values — must be non-negative numbers or nil
    %w[monthly_value total_value].each do |field|
      next if data[field].nil?
      val = data[field].to_f rescue nil
      if val.nil? || val < 0
        Rails.logger.warn("AI returned invalid #{field} '#{data[field]}' for contract #{@contract.id}, setting to nil")
        data[field] = nil
      else
        data[field] = val
      end
    end

    # Coerce notice_period_days — must be a non-negative integer or nil
    if data["notice_period_days"].present?
      val = Integer(data["notice_period_days"]) rescue nil
      if val.nil? || val < 0
        Rails.logger.warn("AI returned invalid notice_period_days '#{data["notice_period_days"]}' for contract #{@contract.id}, setting to nil")
        data["notice_period_days"] = nil
      else
        data["notice_period_days"] = val
      end
    end

    # Coerce auto_renews — must be boolean
    unless data["auto_renews"].nil? || data["auto_renews"].is_a?(TrueClass) || data["auto_renews"].is_a?(FalseClass)
      data["auto_renews"] = ActiveModel::Type::Boolean.new.cast(data["auto_renews"])
    end

    # Sanitize key_clauses array
    if data["key_clauses"].is_a?(Array)
      data["key_clauses"].each do |clause|
        # Clamp confidence_score to 0-100
        if clause["confidence_score"].present?
          score = Integer(clause["confidence_score"]) rescue nil
          clause["confidence_score"] = score ? score.clamp(0, 100) : nil
        end
      end
    else
      data["key_clauses"] = []
    end

    data
  end

  def apply_extraction(data)
    ActiveRecord::Base.transaction do
      if @mode == :incremental
        apply_incremental_extraction(data)
      else
        apply_full_extraction(data)
      end

      # Rebuild key clauses (both modes replace all clauses)
      @contract.key_clauses.destroy_all

      data["key_clauses"]&.each do |clause|
        next unless clause["clause_type"].present? && clause["content"].present?
        next unless KeyClause::CLAUSE_TYPES.include?(clause["clause_type"])

        @contract.key_clauses.create!(
          clause_type: clause["clause_type"],
          content: clause["content"],
          page_reference: clause["page_reference"],
          confidence_score: clause["confidence_score"],
          source_document_id: document_id_lookup[clause["source_document"]]
        )
      end
    end
  end

  # Full mode: only fill blank fields (first-time or re-extract)
  def apply_full_extraction(data)
    update_attrs = {}
    update_attrs[:vendor_name] = data["vendor_name"] if data["vendor_name"].present? && @contract.vendor_name.blank?
    update_attrs[:contract_type] = data["contract_type"] if data["contract_type"].present? && @contract.contract_type.blank?
    update_attrs[:direction] = data["direction"] if data["direction"].present? && Contract::DIRECTIONS.include?(data["direction"]) && @contract.direction == "outbound"
    update_attrs[:start_date] = data["start_date"] if data["start_date"].present? && @contract.start_date.blank?
    update_attrs[:end_date] = data["end_date"] if data["end_date"].present? && @contract.end_date.blank?
    update_attrs[:monthly_value] = data["monthly_value"] if data["monthly_value"].present? && @contract.monthly_value.blank?
    update_attrs[:total_value] = data["total_value"] if data["total_value"].present? && @contract.total_value.blank?
    update_attrs[:auto_renews] = data["auto_renews"] unless data["auto_renews"].nil?
    update_attrs[:renewal_term] = data["renewal_term"] if data["renewal_term"].present? && @contract.renewal_term.blank?
    update_attrs[:notice_period_days] = data["notice_period_days"] if data["notice_period_days"].present? && @contract.notice_period_days.blank?
    update_attrs[:notes] = data["summary"] if data["summary"].present? && @contract.notes.blank?

    @contract.update!(update_attrs) if update_attrs.any?
  end

  # Incremental mode: only update fields where the AI produced a DIFFERENT value
  # than the prior AI extraction. This preserves user edits.
  #
  # Logic: if the user edited a field after AI extraction, the current contract value
  # differs from ai_extracted_data. If the new AI response returns the SAME value as
  # the prior AI extraction, we assume the field didn't change and keep the user's edit.
  # If the AI response differs from the prior AI extraction, the new document actually
  # changed that field, so we overwrite.
  def apply_incremental_extraction(data)
    prior = begin
      JSON.parse(@contract.ai_extracted_data)
    rescue StandardError
      {}
    end

    update_attrs = {}

    # For each field, update only if AI's new value differs from prior AI value
    INCREMENTAL_FIELDS.each do |field, ai_key|
      new_val = data[ai_key]
      prior_val = prior[ai_key]

      next if new_val.nil?
      next if normalize_for_comparison(new_val) == normalize_for_comparison(prior_val)

      # AI produced a genuinely different value — apply it
      update_attrs[field] = new_val
    end

    # Direction has special validation
    if update_attrs[:direction].present? && !Contract::DIRECTIONS.include?(update_attrs[:direction])
      update_attrs.delete(:direction)
    end

    # Notes maps from "summary"
    if data["summary"].present?
      prior_summary = prior["summary"]
      if normalize_for_comparison(data["summary"]) != normalize_for_comparison(prior_summary)
        update_attrs[:notes] = data["summary"]
      end
    end

    @contract.update!(update_attrs) if update_attrs.any?
  end

  INCREMENTAL_FIELDS = {
    vendor_name: "vendor_name",
    contract_type: "contract_type",
    direction: "direction",
    start_date: "start_date",
    end_date: "end_date",
    monthly_value: "monthly_value",
    total_value: "total_value",
    auto_renews: "auto_renews",
    renewal_term: "renewal_term",
    notice_period_days: "notice_period_days"
  }.freeze

  def normalize_for_comparison(val)
    case val
    when nil then nil
    when String then val.strip.downcase
    else val
    end
  end
end
