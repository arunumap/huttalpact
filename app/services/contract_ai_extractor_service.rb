class ContractAiExtractorService
  class ExtractionError < StandardError; end

  # ~400k chars ≈ ~100k tokens, safely under Claude's 200k context window
  MAX_INPUT_CHARS = 400_000

  JSON_SCHEMA = <<~SCHEMA
    {
      "title": "A short descriptive title for this contract",
      "vendor_name": "The other party / vendor / landlord name",
      "premises_address": "The physical address of the property, premises, or service location, or null",
      "contract_type": "One of: lease, service_agreement, maintenance, insurance, software, other",
      "direction": "inbound if the organization receiving this contract is being paid (revenue), outbound if the organization is paying (expense)",
      "start_date": "YYYY-MM-DD or null",
      "end_date": "YYYY-MM-DD or null",
      "next_renewal_date": "YYYY-MM-DD or null — the next date the contract may renew. For auto-renewing contracts, this is typically the end_date.",
      "monthly_value": numeric or null,
      "total_value": numeric or null,
      "auto_renews": true or false,
      "renewal_term": "month-to-month, annual, 2-year, or custom",
      "notice_period_days": numeric or null,
      "key_clauses": [
        {
          "clause_type": "One of: termination, renewal, penalty, sla, price_escalation, liability, insurance_requirement, security_deposit, cam_provision, maintenance_responsibility, subletting_assignment, exclusivity, co_tenancy, parking, signage, hazmat, ada_compliance, subordination, use_restriction, tenant_improvement",
          "content": "The actual clause text or summary",
          "page_reference": "Page X or Section Y",
          "confidence_score": 0-100,
          "source_document": "The exact filename of the document this clause came from"
        }
      ],
      "summary": "2-3 sentence summary of the contract"
    }
  SCHEMA

  LEASE_JSON_SCHEMA = <<~SCHEMA
    {
      "title": "A short descriptive title for this lease",
      "vendor_name": "The landlord / property owner name",
      "premises_address": "The full physical address of the leased premises, or null",
      "contract_type": "lease",
      "direction": "inbound if the tenant is being paid (sublease revenue), outbound if the tenant is paying rent (expense). Default to outbound for standard leases.",
      "start_date": "YYYY-MM-DD or null",
      "end_date": "YYYY-MM-DD or null",
      "next_renewal_date": "YYYY-MM-DD or null — the next date the lease may renew. For auto-renewing leases, use the end_date. If there is a renewal option, use the exercise deadline.",
      "monthly_value": numeric or null (base monthly rent at lease commencement),
      "total_value": numeric or null (total rent over entire lease term if determinable),
      "auto_renews": true or false,
      "renewal_term": "month-to-month, annual, 2-year, or custom",
      "notice_period_days": numeric or null (primary notice period for lease termination/non-renewal),
      "lease_details": {
        "lease_type": "One of: gross, modified_gross, nnn, percentage (or null if unclear)",
        "rentable_sqft": numeric or null,
        "usable_sqft": numeric or null,
        "load_factor": numeric or null (ratio, e.g. 1.15),
        "permitted_use": "Description of permitted use or null",
        "security_deposit": numeric or null,
        "security_deposit_conditions": "Conditions for return/burn-down or null",
        "parking_spaces": integer or null,
        "parking_monthly_cost": numeric or null,
        "free_rent_months": integer or null,
        "rent_commencement_date": "YYYY-MM-DD or null",
        "percentage_rent_breakpoint": numeric or null (annual sales threshold),
        "percentage_rent_rate": numeric or null (percentage above breakpoint),
        "percentage_rent_report_date": "YYYY-MM-DD or null",
        "cam_base_amount": numeric or null (annual base amount),
        "cam_base_year": integer or null (e.g. 2025),
        "cam_cap_percentage": numeric or null (annual cap on increases),
        "cam_cap_type": "One of: cumulative, non_cumulative, none (or null)",
        "cam_reconciliation_month": integer 1-12 or null,
        "cam_audit_rights": true or false,
        "cam_gross_up_provision": true or false,
        "cam_controllable_cap": numeric or null (cap on controllable expenses only),
        "ti_allowance_psf": numeric or null (dollars per square foot),
        "ti_total_amount": numeric or null,
        "ti_deadline": "YYYY-MM-DD or null (use-it-or-lose-it date)",
        "ti_disbursement_type": "One of: lump_sum, draw_schedule, reimbursement (or null)",
        "ti_amortization_rate": numeric or null (if TI structured as loan),
        "ti_amortization_term_months": integer or null,
        "ti_landlord_work_description": "Description or null",
        "ti_tenant_work_description": "Description or null"
      },
      "rent_escalations": [
        {
          "effective_date": "YYYY-MM-DD",
          "base_rent_monthly": numeric or null,
          "base_rent_annual": numeric or null,
          "escalation_type": "One of: fixed_percentage, cpi, fmv_reset, stepped, flat",
          "escalation_value": numeric or null (the percentage, dollar step, or adjustment factor),
          "description": "Human-readable description of this escalation"
        }
      ],
      "lease_options": [
        {
          "option_type": "One of: renewal, expansion, termination, purchase, rofr, rofo",
          "exercise_deadline": "YYYY-MM-DD or null",
          "notice_deadline": "YYYY-MM-DD or null (when written notice must be sent)",
          "term_length_months": integer or null,
          "rent_terms": "Description of pricing during option period or null",
          "penalty_amount": numeric or null (for termination/kick-out fees)",
          "conditions": "Any special conditions or null"
        }
      ],
      "lease_milestones": [
        {
          "milestone_type": "One of: cam_reconciliation, insurance_renewal, estoppel_response, ti_completion, percentage_rent_report, guarantee_burnoff, custom",
          "due_date": "YYYY-MM-DD",
          "description": "Description of what is due",
          "recurring": true or false,
          "recurrence_interval": "One of: monthly, quarterly, annual (or null if not recurring)"
        }
      ],
      "key_clauses": [
        {
          "clause_type": "One of: termination, renewal, penalty, sla, price_escalation, liability, insurance_requirement, security_deposit, cam_provision, maintenance_responsibility, subletting_assignment, exclusivity, co_tenancy, parking, signage, hazmat, ada_compliance, subordination, use_restriction, tenant_improvement",
          "content": "The actual clause text or summary",
          "page_reference": "Page X or Section Y",
          "confidence_score": 0-100,
          "source_document": "The exact filename of the document this clause came from"
        }
      ],
      "summary": "2-3 sentence summary of the lease"
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
    For next_renewal_date: use the specific renewal date if stated. For auto-renewing contracts, use the end_date. If unclear, use null.
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
    For next_renewal_date: use the specific renewal date if stated. For auto-renewing contracts, use the end_date. If unclear, use null.
    For key clauses, return the COMPLETE updated set of clauses from ALL documents (not just the new one).
    For source_document, use the EXACT filename from the document header.

    CONTRACT DOCUMENTS:
  PROMPT

  LEASE_EXTRACTION_PROMPT = <<~PROMPT
    You are a commercial real estate lease analysis specialist. You will receive text from one or more lease documents.
    Each document is labeled with a header like:
      === DOCUMENT 1: "filename.pdf" (Type: Main Contract) ===

    Documents may include a main lease plus addendums, amendments, exhibits, or SOWs.
    When there are multiple documents:
    - Amendments and addendums OVERRIDE conflicting terms in the main lease.
    - Later documents take precedence over earlier ones for the same field.
    - Combine key clauses from ALL documents.

    CRITICAL EXTRACTION INSTRUCTIONS FOR COMMERCIAL LEASES:

    1. RENT ESCALATION SCHEDULE: Extract the COMPLETE rent schedule as a table, not just a summary.
       Include every period where rent changes — the initial rent, each annual increase, CPI adjustments,
       and any stepped increases. Each row needs an effective_date and the new rent amount.
       For percentage-based escalations, calculate the actual dollar amounts if the base is known.

    2. CAM / OPERATING EXPENSES: Look carefully in operating expense sections, additional rent provisions,
       and exhibits. CAM cap provisions are often buried deep — extract them precisely.
       Identify whether expenses are controllable vs. uncontrollable and any gross-up provisions.

    3. OPTIONS: Extract ALL option types — renewal, expansion, termination/kick-out, purchase, ROFR, ROFO.
       For each option, the NOTICE DEADLINE is critical (when written notice must be sent).
       This is often different from the exercise deadline. Get both dates.

    4. TENANT IMPROVEMENTS: Extract the TI allowance (per SF and total), the deadline for utilization
       (use-it-or-lose-it), disbursement method, and whether TI is structured as a loan with amortization.
       Separate landlord work from tenant work.

    5. MILESTONES: Generate milestone entries for recurring obligations found in the lease:
       insurance certificate renewals, estoppel certificate response windows, CAM reconciliation dates,
       percentage rent reporting dates, personal guarantee burn-off dates.

    Return ONLY valid JSON with these fields (no markdown, no explanation):
    #{LEASE_JSON_SCHEMA}

    Be precise with dates and monetary values. If information is not found, use null.
    For direction: standard leases where the tenant pays rent are "outbound". Subleases where the tenant receives rent are "inbound".
    For next_renewal_date: use the specific renewal date if stated. For auto-renewing leases, use the end_date. If there is a renewal option, use its exercise deadline.
    For key clauses, include all important provisions that affect renewals, costs, tenant rights, and obligations.
    For source_document, use the EXACT filename from the document header.

    CONTRACT DOCUMENTS:
  PROMPT

  LEASE_INCREMENTAL_PROMPT = <<~PROMPT
    You are a commercial real estate lease analysis specialist. A lease has already been analyzed and you are now given an additional document (addendum, amendment, exhibit, etc.) that was just uploaded.

    PRIOR EXTRACTION RESULT (JSON):
    %{prior_json}

    A new document has been added. Re-analyze the full lease considering this new document.
    The new document may override or supplement terms from the prior extraction.
    Amendments and addendums OVERRIDE conflicting terms in the main lease.

    CRITICAL: Pay special attention to:
    - Changes to rent amounts or escalation schedules
    - New or modified options (renewal, termination, expansion)
    - Changes to CAM caps or base year
    - TI allowance modifications or deadline extensions
    - New milestone obligations

    Return ONLY valid JSON with these fields (no markdown, no explanation):
    #{LEASE_JSON_SCHEMA}

    Also include an additional field:
      "changes_summary": "A brief human-readable summary of what changed compared to the prior extraction"

    Be precise with dates and monetary values. If information is not found, use null.
    For next_renewal_date: use the specific renewal date if stated. For auto-renewing leases, use the end_date.
    For key clauses, return the COMPLETE updated set of clauses from ALL documents.
    For source_document, use the EXACT filename from the document header.

    CONTRACT DOCUMENTS:
  PROMPT

  # Lease-indicative terms for auto-detection
  LEASE_INDICATORS = %w[landlord tenant premises lease rent commencement demised leasehold lessee lessor].freeze
  LEASE_INDICATOR_THRESHOLD = 3

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
      if org.at_extraction_limit? && !org.extraction_overage_enabled?
        Rails.logger.info("AI extraction blocked for contract #{@contract.id}: org #{org.id} at extraction limit")
        raise ExtractionLimitReachedError, "Monthly AI extraction limit reached (#{org.plan_extraction_limit} for #{org.plan} plan)"
      end
    end

    document_text = build_document_text
    return if document_text.blank?

    # Auto-detect lease type from document text if contract_type isn't set
    @lease_type_auto_detected = detect_and_set_lease_type!(document_text)

    # Atomic reentrance guard: only proceed if we can claim the "processing" status
    rows_updated = Contract.where(id: @contract.id)
      .where.not(extraction_status: "processing")
      .update_all(extraction_status: "processing")
    return if rows_updated == 0

    @contract.reload

    prompt = build_prompt(document_text)

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    input_tokens = 0
    output_tokens = 0

    response = client.messages(
      parameters: extraction_config.api_parameters.merge(
        system: "You are a contract analysis assistant. Respond with ONLY valid JSON. No preamble, no explanation, no markdown fences — just the raw JSON object.",
        messages: [ { role: "user", content: prompt } ]
      )
    )
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
    input_tokens = response.dig("usage", "input_tokens").to_i
    output_tokens = response.dig("usage", "output_tokens").to_i

    # Check if the response was truncated due to max_tokens limit
    stop_reason = response["stop_reason"]
    if stop_reason == "max_tokens"
      max_tok = extraction_config.max_tokens
      Rails.logger.warn("AI extraction truncated for contract #{@contract.id}: hit max_tokens limit (#{max_tok}). Increase max_tokens in AI config.")
      @contract.update!(extraction_status: "failed")
      log_ai_usage!(
        ai_model: extraction_config.ai_model,
        input_tokens:,
        output_tokens:,
        duration_ms:,
        success: false,
        error_message: "Response truncated: output hit max_tokens limit (#{max_tok}). Increase max_tokens in AI config."
      )
      raise ExtractionError, "AI response truncated at #{max_tok} max_tokens — increase max_tokens in the AI extraction config for this type"
    end

    raw_text = response.dig("content", 0, "text")
    raise ExtractionError, "No content in AI response" if raw_text.blank?

    # Strip markdown code fences if present
    json_text = raw_text.gsub(/\A```(?:json)?\n?/, "").gsub(/\n?```\z/, "").strip

    # If the response doesn't start with '{', try to extract JSON object from the text
    # Claude sometimes prefixes its response with conversational text
    unless json_text.start_with?("{")
      json_match = json_text.match(/\{.*\}/m)
      raise JSON::ParserError, "No JSON object found in AI response: '#{json_text[0, 40]}...'" unless json_match
      json_text = json_match[0]
    end

    extracted = JSON.parse(json_text)

    # Sanitize/coerce AI output before applying to models
    sanitize_extracted_data!(extracted)

    apply_extraction(extracted)

    update_attrs = {
      extraction_status: "completed",
      ai_extracted_data: extracted.except("changes_summary").to_json
    }
    update_attrs[:last_changes_summary] = extracted["changes_summary"] if extracted["changes_summary"].present?

    # Add auto-detect notice to changes summary
    if @lease_type_auto_detected
      auto_detect_msg = "Contract type auto-detected as Lease based on document content."
      update_attrs[:last_changes_summary] = [ auto_detect_msg, update_attrs[:last_changes_summary] ].compact.join(" ")
    end

    @contract.update!(update_attrs)

    # Track extraction usage against plan limits
    usage_result = @contract.organization&.consume_extraction_usage!
    if usage_result && !usage_result.allowed?
      Rails.logger.warn("AI extraction usage increment blocked post-success for contract #{@contract.id}: org #{@contract.organization_id} at extraction limit")
    elsif usage_result&.overage?
      enqueue_overage_billing(usage_result)
    end

    log_ai_usage!(
      ai_model: extraction_config.ai_model,
      input_tokens:,
      output_tokens:,
      duration_ms:,
      success: true
    )

    extracted
  rescue JSON::ParserError => e
    @contract.update!(extraction_status: "failed")
    log_ai_usage!(
      ai_model: extraction_config.ai_model,
      input_tokens:,
      output_tokens:,
      duration_ms:,
      success: false,
      error_message: "JSON parse error: #{e.message}"
    )
    Rails.logger.error("AI extraction JSON parse error for contract #{@contract.id}: #{e.message}")
    raise ExtractionError, "Failed to parse AI response as JSON"
  rescue ExtractionLimitReachedError
    # Don't change extraction status — this is a billing limit, not an extraction failure
    raise
  rescue Faraday::ClientError => e
    @contract.update!(extraction_status: "failed")
    log_ai_usage!(
      ai_model: extraction_config.ai_model,
      input_tokens:,
      output_tokens:,
      duration_ms:,
      success: false,
      error_message: "API error: #{e.message}"
    )
    body = e.response&.dig(:body) rescue nil
    Rails.logger.error("AI extraction API error for contract #{@contract.id}: #{e.message} — #{body}")
    raise e
  rescue Net::ReadTimeout, Net::OpenTimeout => e
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round rescue nil
    timeout_secs = extraction_config.resolved_timeout
    error_msg = "API timeout after #{timeout_secs}s (#{e.class.name}) — try increasing request_timeout in AI config"
    @contract.update!(extraction_status: "failed")
    log_ai_usage!(
      ai_model: extraction_config.ai_model,
      input_tokens:,
      output_tokens:,
      duration_ms:,
      success: false,
      error_message: error_msg
    )
    Rails.logger.error("AI extraction timeout for contract #{@contract.id}: #{error_msg}")
    raise e
  rescue => e
    @contract.update!(extraction_status: "failed")
    log_ai_usage!(
      ai_model: extraction_config.ai_model,
      input_tokens:,
      output_tokens:,
      duration_ms:,
      success: false,
      error_message: e.message
    )
    Rails.logger.error("AI extraction failed for contract #{@contract.id}: #{e.message}")
    raise e
  end

  private

  def client
    @client ||= Anthropic::Client.new(
      access_token: api_key,
      request_timeout: extraction_config.resolved_timeout
    )
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

  def log_ai_usage!(ai_model:, input_tokens:, output_tokens:, duration_ms:, success:, error_message: nil)
    organization = @contract.organization
    return unless organization

    AiUsageLog.create!(
      organization:,
      contract: @contract,
      ai_model:,
      input_tokens:,
      output_tokens:,
      extraction_mode: @mode.to_s,
      success:,
      error_message:,
      duration_ms:,
      ai_extraction_config: extraction_config.persisted? ? extraction_config : nil
    )
  rescue => e
    Rails.logger.error("Failed to write AI usage log for contract #{@contract.id}: #{e.message}")
  end

  def enqueue_overage_billing(usage_result)
    organization = @contract.organization
    return unless organization

    period_start = usage_result.extraction_period_start
    usage_position = usage_result.usage_position

    overage_charge = ExtractionOverageCharge.create!(
      organization:,
      contract: @contract,
      extraction_period_start_at: period_start,
      usage_position:,
      overage_cents: usage_result.overage_cents,
      idempotency_key: overage_idempotency_key(organization.id, period_start, usage_position)
    )

    AuditLog.create(
      organization:,
      contract: @contract,
      action: "extraction_overage",
      details: "Usage position #{usage_position} billed at #{usage_result.overage_cents} cents (period start #{period_start.to_date})"
    )

    BillExtractionOverageJob.perform_later(overage_charge.id)
  rescue ActiveRecord::RecordNotUnique
    existing = ExtractionOverageCharge.find_by(
      organization_id: organization.id,
      extraction_period_start_at: period_start,
      usage_position:
    )
    BillExtractionOverageJob.perform_later(existing.id) if existing
  rescue => e
    Rails.logger.error("Failed to enqueue overage billing for contract #{@contract.id}: #{e.message}")
    Sentry.capture_exception(e, extra: { contract_id: @contract.id, organization_id: organization.id }) if defined?(Sentry) && Sentry.initialized?
  end

  def overage_idempotency_key(organization_id, period_start, usage_position)
    "overage-#{organization_id}-#{period_start.utc.iso8601}-#{usage_position}"
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
      prompt_template = lease_extraction? ? LEASE_INCREMENTAL_PROMPT : INCREMENTAL_EXTRACTION_PROMPT
      format(prompt_template, prior_json: prior_json) + new_doc_hint + "\n#{document_text}"
    else
      prompt_template = lease_extraction? ? LEASE_EXTRACTION_PROMPT : FULL_EXTRACTION_PROMPT
      "#{prompt_template}\n#{document_text}"
    end
  end

  def lease_extraction?
    @lease_extraction ||= @contract.contract_type == "lease"
  end

  # Resolve the extraction type string and fetch active DB config
  def extraction_config
    @extraction_config ||= begin
      type = if lease_extraction?
               @mode == :incremental ? "lease_incremental" : "lease_full"
      else
               @mode == :incremental ? "generic_incremental" : "generic_full"
      end
      AiExtractionConfig.active_for(type)
    end
  end

  def detect_and_set_lease_type!(document_text)
    # Skip detection only if a specific (non-"other") type was explicitly set by the user
    return false if @contract.contract_type.present? && @contract.contract_type != "other"

    text_lower = document_text.downcase
    matches = LEASE_INDICATORS.count { |term| text_lower.include?(term) }

    if matches >= LEASE_INDICATOR_THRESHOLD
      @contract.update_column(:contract_type, "lease")
      @contract.reload
      Rails.logger.info("Auto-detected contract #{@contract.id} as lease (#{matches} indicator terms found)")
      true
    else
      false
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
    %w[start_date end_date next_renewal_date].each do |field|
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

    # Sanitize lease-specific data if present
    sanitize_lease_data!(data) if data["lease_details"].is_a?(Hash) || data["rent_escalations"].is_a?(Array) || data["lease_options"].is_a?(Array) || data["lease_milestones"].is_a?(Array)

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

      # Apply lease-specific data if present (lease_details, rent_escalations, options, milestones)
      apply_lease_extraction(data) if lease_extraction? || data["lease_details"].is_a?(Hash)
    end
  end

  # Full mode: only fill blank fields (first-time or re-extract)
  def apply_full_extraction(data)
    update_attrs = {}
    update_attrs[:title] = data["title"] if data["title"].present? && @contract.title.blank?
    update_attrs[:vendor_name] = data["vendor_name"] if data["vendor_name"].present? && @contract.vendor_name.blank?
    update_attrs[:premises_address] = data["premises_address"] if data["premises_address"].present? && @contract.premises_address.blank?
    update_attrs[:contract_type] = data["contract_type"] if data["contract_type"].present? && @contract.contract_type.blank?
    update_attrs[:direction] = data["direction"] if data["direction"].present? && Contract::DIRECTIONS.include?(data["direction"]) && @contract.direction == "outbound"
    update_attrs[:start_date] = data["start_date"] if data["start_date"].present? && @contract.start_date.blank?
    update_attrs[:end_date] = data["end_date"] if data["end_date"].present? && @contract.end_date.blank?
    update_attrs[:next_renewal_date] = data["next_renewal_date"] if data["next_renewal_date"].present? && @contract.next_renewal_date.blank?
    update_attrs[:monthly_value] = data["monthly_value"] if data["monthly_value"].present? && @contract.monthly_value.blank?
    update_attrs[:total_value] = data["total_value"] if data["total_value"].present? && @contract.total_value.blank?
    update_attrs[:auto_renews] = data["auto_renews"] unless data["auto_renews"].nil?
    update_attrs[:renewal_term] = data["renewal_term"] if data["renewal_term"].present? && @contract.renewal_term.blank?
    update_attrs[:notice_period_days] = data["notice_period_days"] if data["notice_period_days"].present? && @contract.notice_period_days.blank?
    update_attrs[:ai_summary] = data["summary"] if data["summary"].present?

    @contract.update!(update_attrs) if update_attrs.any?

    # Fallback: compute next_renewal_date from end_date if still blank
    compute_next_renewal_date!
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

    # AI summary — always update if changed (separate from user notes)
    if data["summary"].present?
      prior_summary = prior["summary"]
      if normalize_for_comparison(data["summary"]) != normalize_for_comparison(prior_summary)
        update_attrs[:ai_summary] = data["summary"]
      end
    end

    @contract.update!(update_attrs) if update_attrs.any?

    # Fallback: compute next_renewal_date from end_date if still blank
    compute_next_renewal_date!
  end

  INCREMENTAL_FIELDS = {
    title: "title",
    vendor_name: "vendor_name",
    premises_address: "premises_address",
    contract_type: "contract_type",
    direction: "direction",
    start_date: "start_date",
    end_date: "end_date",
    next_renewal_date: "next_renewal_date",
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

  # Fallback: when AI doesn't return next_renewal_date, compute it from end_date
  # for auto-renewing contracts. This ensures renewals dashboard and alerts work.
  def compute_next_renewal_date!
    return if @contract.next_renewal_date.present?
    return unless @contract.auto_renews?
    return unless @contract.end_date.present?

    @contract.update_column(:next_renewal_date, @contract.end_date)
    @contract.reload
  end

  # --- Lease-specific sanitization and application ---

  def sanitize_lease_data!(data)
    # Sanitize lease_details hash
    if data["lease_details"].is_a?(Hash)
      ld = data["lease_details"]

      # Enum coercion
      ld["lease_type"] = nil if ld["lease_type"].present? && !LeaseDetail::LEASE_TYPES.include?(ld["lease_type"])
      ld["cam_cap_type"] = nil if ld["cam_cap_type"].present? && !LeaseDetail::CAM_CAP_TYPES.include?(ld["cam_cap_type"])
      ld["ti_disbursement_type"] = nil if ld["ti_disbursement_type"].present? && !LeaseDetail::TI_DISBURSEMENT_TYPES.include?(ld["ti_disbursement_type"])

      # Numeric coercion (non-negative)
      %w[rentable_sqft usable_sqft load_factor security_deposit parking_monthly_cost
         percentage_rent_breakpoint percentage_rent_rate cam_base_amount cam_cap_percentage
         cam_controllable_cap ti_allowance_psf ti_total_amount ti_amortization_rate].each do |field|
        next if ld[field].nil?
        val = ld[field].to_f rescue nil
        ld[field] = (val && val >= 0) ? val : nil
      end

      # Integer coercion (non-negative)
      %w[parking_spaces free_rent_months cam_base_year ti_amortization_term_months].each do |field|
        next if ld[field].nil?
        val = Integer(ld[field]) rescue nil
        ld[field] = (val && val >= 0) ? val : nil
      end

      # CAM reconciliation month: must be 1-12
      if ld["cam_reconciliation_month"].present?
        val = Integer(ld["cam_reconciliation_month"]) rescue nil
        ld["cam_reconciliation_month"] = (val && val >= 1 && val <= 12) ? val : nil
      end

      # Boolean coercion
      %w[cam_audit_rights cam_gross_up_provision].each do |field|
        unless ld[field].nil? || ld[field].is_a?(TrueClass) || ld[field].is_a?(FalseClass)
          ld[field] = ActiveModel::Type::Boolean.new.cast(ld[field])
        end
      end

      # Date coercion
      %w[rent_commencement_date percentage_rent_report_date ti_deadline].each do |field|
        next if ld[field].nil?
        begin
          Date.parse(ld[field].to_s)
        rescue Date::Error, ArgumentError
          ld[field] = nil
        end
      end
    else
      data["lease_details"] = nil
    end

    # Sanitize rent_escalations array
    if data["rent_escalations"].is_a?(Array)
      data["rent_escalations"].each do |esc|
        # effective_date is required
        if esc["effective_date"].present?
          begin
            Date.parse(esc["effective_date"].to_s)
          rescue Date::Error, ArgumentError
            esc["effective_date"] = nil
          end
        end

        # escalation_type enum
        esc["escalation_type"] = nil if esc["escalation_type"].present? && !RentEscalation::ESCALATION_TYPES.include?(esc["escalation_type"])

        # Numeric coercion
        %w[base_rent_monthly base_rent_annual escalation_value].each do |field|
          next if esc[field].nil?
          val = esc[field].to_f rescue nil
          esc[field] = val
        end
      end
      # Remove entries without required fields
      data["rent_escalations"].reject! { |esc| esc["effective_date"].blank? || esc["escalation_type"].blank? }
    else
      data["rent_escalations"] = []
    end

    # Sanitize lease_options array
    if data["lease_options"].is_a?(Array)
      data["lease_options"].each do |opt|
        opt["option_type"] = nil if opt["option_type"].present? && !LeaseOption::OPTION_TYPES.include?(opt["option_type"])

        %w[exercise_deadline notice_deadline].each do |field|
          next if opt[field].nil?
          begin
            Date.parse(opt[field].to_s)
          rescue Date::Error, ArgumentError
            opt[field] = nil
          end
        end

        if opt["term_length_months"].present?
          val = Integer(opt["term_length_months"]) rescue nil
          opt["term_length_months"] = (val && val > 0) ? val : nil
        end

        if opt["penalty_amount"].present?
          val = opt["penalty_amount"].to_f rescue nil
          opt["penalty_amount"] = (val && val >= 0) ? val : nil
        end
      end
      data["lease_options"].reject! { |opt| opt["option_type"].blank? }
    else
      data["lease_options"] = []
    end

    # Sanitize lease_milestones array
    if data["lease_milestones"].is_a?(Array)
      data["lease_milestones"].each do |ms|
        ms["milestone_type"] = nil if ms["milestone_type"].present? && !LeaseMilestone::MILESTONE_TYPES.include?(ms["milestone_type"])

        if ms["due_date"].present?
          begin
            Date.parse(ms["due_date"].to_s)
          rescue Date::Error, ArgumentError
            ms["due_date"] = nil
          end
        end

        unless ms["recurring"].nil? || ms["recurring"].is_a?(TrueClass) || ms["recurring"].is_a?(FalseClass)
          ms["recurring"] = ActiveModel::Type::Boolean.new.cast(ms["recurring"])
        end

        ms["recurrence_interval"] = nil if ms["recurrence_interval"].present? && !LeaseMilestone::RECURRENCE_INTERVALS.include?(ms["recurrence_interval"])
      end
      data["lease_milestones"].reject! { |ms| ms["milestone_type"].blank? || ms["due_date"].blank? }
    else
      data["lease_milestones"] = []
    end
  end

  def apply_lease_extraction(data)
    # Destroy and re-create lease detail (1:1)
    @contract.lease_detail&.destroy
    if data["lease_details"].is_a?(Hash)
      ld = data["lease_details"]
      @contract.create_lease_detail!(
        lease_type: ld["lease_type"],
        rentable_sqft: ld["rentable_sqft"],
        usable_sqft: ld["usable_sqft"],
        load_factor: ld["load_factor"],
        permitted_use: ld["permitted_use"],
        security_deposit: ld["security_deposit"],
        security_deposit_conditions: ld["security_deposit_conditions"],
        parking_spaces: ld["parking_spaces"],
        parking_monthly_cost: ld["parking_monthly_cost"],
        free_rent_months: ld["free_rent_months"],
        rent_commencement_date: ld["rent_commencement_date"],
        percentage_rent_breakpoint: ld["percentage_rent_breakpoint"],
        percentage_rent_rate: ld["percentage_rent_rate"],
        percentage_rent_report_date: ld["percentage_rent_report_date"],
        cam_base_amount: ld["cam_base_amount"],
        cam_base_year: ld["cam_base_year"],
        cam_cap_percentage: ld["cam_cap_percentage"],
        cam_cap_type: ld["cam_cap_type"],
        cam_reconciliation_month: ld["cam_reconciliation_month"],
        cam_audit_rights: ld["cam_audit_rights"] || false,
        cam_gross_up_provision: ld["cam_gross_up_provision"] || false,
        cam_controllable_cap: ld["cam_controllable_cap"],
        ti_allowance_psf: ld["ti_allowance_psf"],
        ti_total_amount: ld["ti_total_amount"],
        ti_deadline: ld["ti_deadline"],
        ti_disbursement_type: ld["ti_disbursement_type"],
        ti_amortization_rate: ld["ti_amortization_rate"],
        ti_amortization_term_months: ld["ti_amortization_term_months"],
        ti_landlord_work_description: ld["ti_landlord_work_description"],
        ti_tenant_work_description: ld["ti_tenant_work_description"]
      )
    end

    # Destroy and re-create rent escalations
    @contract.rent_escalations.destroy_all
    data["rent_escalations"]&.each_with_index do |esc, idx|
      @contract.rent_escalations.create!(
        effective_date: esc["effective_date"],
        base_rent_monthly: esc["base_rent_monthly"],
        base_rent_annual: esc["base_rent_annual"],
        escalation_type: esc["escalation_type"],
        escalation_value: esc["escalation_value"],
        description: esc["description"],
        position: idx
      )
    end

    # Destroy and re-create lease options
    @contract.lease_options.destroy_all
    data["lease_options"]&.each_with_index do |opt, idx|
      @contract.lease_options.create!(
        option_type: opt["option_type"],
        exercise_deadline: opt["exercise_deadline"],
        notice_deadline: opt["notice_deadline"],
        term_length_months: opt["term_length_months"],
        rent_terms: opt["rent_terms"],
        penalty_amount: opt["penalty_amount"],
        conditions: opt["conditions"],
        position: idx
      )
    end

    # Destroy and re-create lease milestones
    @contract.lease_milestones.destroy_all
    data["lease_milestones"]&.each do |ms|
      @contract.lease_milestones.create!(
        organization: @contract.organization,
        milestone_type: ms["milestone_type"],
        due_date: ms["due_date"],
        description: ms["description"],
        recurring: ms["recurring"] || false,
        recurrence_interval: ms["recurrence_interval"]
      )
    end
  end
end
