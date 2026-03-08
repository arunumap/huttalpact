class ContractReviewOrchestrationService
  def initialize(contract, extraction_result:, mode:)
    @contract = contract
    @extraction_result = extraction_result.to_h.deep_stringify_keys
    @mode = mode.to_sym
  end

  def call
    return if review_field_payloads.empty?

    ActsAsTenant.with_tenant(@contract.organization) do
      @contract.with_lock do
        previous_review = latest_review
        previous_fields = previous_review_fields(previous_review)

        supersede_open_review!

        @review = @contract.contract_reviews.create!(
          organization: @contract.organization,
          ai_usage_log: latest_ai_usage_log,
          review_trigger: review_trigger
        )

        applicable_payloads.each do |payload|
          persist_review_field(payload, previous_fields)
        end

        transition_contract_to_in_review!
        @review.refresh_summary!
        @review
      end
    end
  end

  private

  def latest_review
    @contract.contract_reviews.recent.first
  end

  def current_open_review
    @contract.contract_reviews.open.recent.first
  end

  def previous_review_fields(previous_review)
    return {} unless previous_review

    ContractReviewField.unscoped
      .where(contract_review_id: previous_review.id)
      .includes(:reviewed_by)
      .index_by { |field| field_identity(field) }
  end

  def supersede_open_review!
    return unless current_open_review

    current_open_review.update!(status: "superseded", superseded_at: Time.current)
  end

  def latest_ai_usage_log
    @contract.ai_usage_logs.order(created_at: :desc).first
  end

  def review_trigger
    @mode == :incremental ? "addendum_upload" : "initial_extraction"
  end

  def review_field_payloads
    @review_field_payloads ||= Array(@extraction_result["review_fields"]).map { |payload| payload.to_h.deep_stringify_keys }
  end

  def changed_field_keys
    @changed_field_keys ||= Array(@extraction_result["changed_field_keys"]).map(&:to_s)
  end

  def impacted_field_keys
    @impacted_field_keys ||= Array(@extraction_result["impacted_field_keys"]).map(&:to_s)
  end

  def review_field_payloads_by_key
    @review_field_payloads_by_key ||= review_field_payloads.group_by { |payload| payload["field_key"] }
  end

  def applicable_payloads
    @applicable_payloads ||= review_field_payloads.select do |payload|
      FieldReadinessPolicy.applicable?(payload, sibling_payloads: review_field_payloads_by_key)
    end
  end

  def persist_review_field(payload, previous_fields)
    previous_field = previous_fields[field_identity(payload)]
    carry_forward = carry_forward?(payload, previous_field)

    readiness = carry_forward ? nil : readiness_for(payload)

    field = @review.contract_review_fields.create!(
      contract: @contract,
      organization: @contract.organization,
      field_key: payload["field_key"],
      field_index: payload["field_index"],
      extracted_value: payload["value"],
      current_value: payload["current_canonical_value"],
      approved_value: carry_forward ? previous_field&.effective_value : nil,
      readiness_bucket: carry_forward ? previous_field.readiness_bucket : readiness.bucket,
      review_status: carry_forward ? previous_field.review_status : "pending",
      confidence_score: payload["confidence_score"],
      source_quality_flag: payload["source_quality"],
      readiness_reasons: carry_forward ? (previous_field.readiness_reasons || []) : readiness.reasons,
      source_document: resolve_source_document(payload["source_document"]),
      source_document_name: payload["source_document"],
      source_locator: payload["source_reference"],
      source_span: source_span_for(payload),
      reviewed_by: carry_forward ? previous_field.reviewed_by : nil,
      reviewed_at: carry_forward ? previous_field.reviewed_at : nil,
      review_note: carry_forward ? previous_field.review_note : nil
    )

    create_review_events!(field, previous_field:, payload:, carry_forward:)
    create_conflict!(field, previous_field:, payload:) if create_conflict?(payload)

    field
  end

  def create_review_events!(field, previous_field:, payload:, carry_forward:)
    metadata = {
      "changed" => changed_field?(payload),
      "impacted" => impacted_field?(payload),
      "carried_forward" => carry_forward,
      "review_trigger" => review_trigger
    }

    field.contract_review_field_events.create!(
      contract_review: @review,
      contract: @contract,
      organization: @contract.organization,
      action: "extracted",
      from_review_status: previous_field&.review_status,
      to_review_status: field.review_status,
      from_value: previous_field&.effective_value,
      to_value: field.extracted_value,
      metadata:
    )

    return unless @mode == :incremental
    return unless previous_field&.reviewed?
    return unless impacted_field?(payload)

    field.contract_review_field_events.create!(
      contract_review: @review,
      contract: @contract,
      organization: @contract.organization,
      action: "reopened",
      from_review_status: previous_field.review_status,
      to_review_status: field.review_status,
      from_value: previous_field.effective_value,
      to_value: field.extracted_value,
      metadata:
    )
  end

  def create_conflict!(field, previous_field:, payload:)
    field.contract_review_conflicts.create!(
      contract_review: @review,
      contract: @contract,
      organization: @contract.organization,
      conflict_type: conflict_type_for(payload),
      blocks_activation: payload["gates_activation"] || derived_dependency_missing?(payload),
      summary: conflict_summary_for(payload),
      details: payload["conflict_candidate_reason"],
      extracted_value: payload["value"],
      approved_value: previous_field&.effective_value,
      alert_family_keys: Array(payload["alert_family_keys"]),
      source_span: source_span_for(payload)
    )
  end

  def carry_forward?(payload, previous_field)
    return false unless @mode == :incremental
    return false unless previous_field

    !impacted_field?(payload)
  end

  def readiness_for(payload)
    context = { "dependency_payloads" => review_field_payloads_by_key }
    FieldReadinessPolicy.new.call(payload, context: context)
  end

  def derived_dependency_missing?(payload)
    return false unless payload["source_type"] == "derived"

    Array(payload["derived_input_keys"]).any? do |dependency_key|
      dependency_payloads = review_field_payloads_by_key[dependency_key]
      dependency_payloads.blank? || dependency_payloads.all? { |dependency_payload| dependency_payload["value"].blank? }
    end
  end

  def create_conflict?(payload)
    payload["conflict_candidate"] || derived_dependency_missing?(payload)
  end

  def conflict_type_for(payload)
    return "derived_dependency_missing" if derived_dependency_missing?(payload)
    return "missing_extracted_value" if payload["value"].blank?
    return "unexpected_extracted_value" if payload["current_canonical_value"].blank? && payload["value"].present?

    "value_mismatch"
  end

  def conflict_summary_for(payload)
    return "Derived dependencies are incomplete for #{payload["field_key"]}." if derived_dependency_missing?(payload)
    return "The extractor did not find a value for #{payload["field_key"]}." if payload["value"].blank?

    payload["conflict_candidate_reason"].presence || "The extractor output differs from the current contract state for #{payload["field_key"]}."
  end

  def changed_field?(payload)
    changed_field_keys.include?(payload["field_key"])
  end

  def impacted_field?(payload)
    impacted_field_keys.include?(payload["field_key"]) || payload["impacted_by_new_document"]
  end

  def transition_contract_to_in_review!
    return if Contract::INACTIVE_STATUSES.include?(@contract.status)
    return if @contract.in_review?

    @contract.update!(status: "in_review")
  end

  def resolve_source_document(filename)
    return if filename.blank?

    @resolve_source_document ||= @contract.contract_documents.completed.index_by(&:filename)
    @resolve_source_document[filename]
  end

  def source_span_for(payload)
    {
      "excerpt" => payload["source_excerpt"],
      "precedence_hint" => payload["precedence_hint"],
      "supersedes_prior_value" => payload["supersedes_prior_value"],
      "impacted_by_new_document" => payload["impacted_by_new_document"]
    }.compact
  end

  def field_identity(field_or_payload)
    if field_or_payload.respond_to?(:field_key)
      [ field_or_payload.field_key, field_or_payload.field_index ]
    elsif field_or_payload.is_a?(Hash)
      [ field_or_payload["field_key"], field_or_payload["field_index"] ]
    end
  end
end
