class ContractReviewCreatorService
  def initialize(contract:, extracted_data:, mode: :full)
    @contract = contract
    @extracted_data = extracted_data
    @mode = mode
    @field_metadata = extracted_data["field_metadata"] || {}
  end

  def call
    ActiveRecord::Base.transaction do
      @contract.lock!
      @contract.contract_reviews.active.update_all(status: "completed", completed_at: Time.current)

      review = create_review
      create_review_fields(review)
      resolve_source_locators(review)

      review.update!(total_fields: review.fields.count)

      @contract.update!(status: "in_review") unless @contract.in_review?

      review
    end
  end

  private

  def create_review
    @contract.contract_reviews.create!(
      organization: @contract.organization,
      status: "pending",
      review_type: @mode.to_s,
      confidence_threshold: default_confidence_threshold,
      ai_extraction_snapshot: @extracted_data.to_json
    )
  end

  def create_review_fields(review)
    catalog_fields = ReviewFieldCatalog.for_contract_type(@contract.contract_type)
    locator_service = build_locator_service

    catalog_fields.each do |catalog_entry|
      value = extract_value(catalog_entry.field_name)
      next if value.nil? && @mode == :full

      if @mode == :incremental
        current_value = current_canonical_value(catalog_entry.field_name)
        next if values_equivalent?(value, current_value)
      end

      metadata = @field_metadata[catalog_entry.field_name] || {}
      confidence = metadata["confidence"]
      needs_review = confidence.nil? || confidence < default_confidence_threshold
      source_excerpt = metadata["source_excerpt"]
      source_locator = build_source_locator(metadata)
      source_match_strategy = nil
      case catalog_entry.field_name
      when "lease_milestones"
        value = enrich_lease_milestones_with_evidence(value, metadata, locator_service)
      when "key_clauses"
        value = enrich_key_clauses_with_evidence(value, metadata, locator_service)
      end

      has_item_evidence = milestone_evidence_present?(value) || key_clause_evidence_present?(value)

      if needs_review && source_excerpt.blank? && !has_item_evidence
        inferred_evidence = infer_evidence_from_value(
          value: value,
          locator_service: locator_service,
          source_locator: source_locator
        )
        source_excerpt = inferred_evidence[:source_excerpt]
        source_locator = inferred_evidence[:source_locator] if inferred_evidence[:source_locator].present?
        source_match_strategy = inferred_evidence[:source_match_strategy]
      end

      reasoning = metadata["reasoning"]
      if needs_review && source_excerpt.blank? && !has_item_evidence
        reasoning = [ reasoning, "Source excerpt unavailable; verify this value manually against the document." ]
          .compact
          .join(" ")
      end

      review.fields.create!(
        field_name: catalog_entry.field_name,
        field_group: catalog_entry.field_group,
        display_name: catalog_entry.display_name,
        extracted_value: encode_value(value),
        confidence: confidence,
        source_excerpt: source_excerpt,
        reasoning: reasoning,
        source_locator: source_locator,
        source_match_strategy: source_match_strategy,
        needs_review: needs_review,
        status: "pending",
        position: catalog_entry.position
      )
    end
  end

  def extract_value(field_name)
    parts = field_name.split(".")
    if parts.length == 2
      parent = @extracted_data[parts[0]]
      return nil unless parent.is_a?(Hash)

      parent[parts[1]]
    else
      @extracted_data[field_name]
    end
  end

  def current_canonical_value(field_name)
    parts = field_name.split(".")
    if parts.length == 2 && parts[0] == "lease_details"
      @contract.lease_detail&.public_send(parts[1])
    elsif field_name == "rent_escalations"
      @contract.rent_escalations.order(:position).map { |e| serialize_escalation(e) }
    elsif field_name == "lease_options"
      @contract.lease_options.order(:position).map { |o| serialize_option(o) }
    elsif field_name == "lease_milestones"
      @contract.lease_milestones.map { |m| serialize_milestone(m) }
    elsif field_name == "key_clauses"
      @contract.key_clauses.map { |c| serialize_clause(c) }
    elsif field_name == "summary"
      @contract.ai_summary
    else
      @contract.public_send(field_name)
    end
  rescue NoMethodError
    nil
  end

  def values_equivalent?(new_val, current_val)
    normalize(new_val) == normalize(current_val)
  end

  def normalize(val)
    case val
    when nil then nil
    when String then val.strip.downcase
    when Numeric then val.to_f
    when Array then val.map { |v| normalize(v) }
    when Hash then val.transform_values { |v| normalize(v) }
    when true, false then val
    else val.to_s.strip.downcase
    end
  end

  def encode_value(value)
    value.to_json
  end

  def build_source_locator(metadata)
    locator = {}
    locator["page_hint"] = metadata["page_hint"] if metadata["page_hint"].present?
    locator["section_hint"] = metadata["section_hint"] if metadata["section_hint"].present?
    locator.presence
  end

  def resolve_source_locators(review)
    documents = build_documents_for_locator
    return if documents.empty?

    locator_service = ReviewSourceLocatorService.new(documents)
    locator_service.resolve_all(review.fields.where(source_match_strategy: nil))
  end

  def build_locator_service
    documents = build_documents_for_locator
    return if documents.empty?

    ReviewSourceLocatorService.new(documents)
  end

  def infer_evidence_from_value(value:, locator_service:, source_locator:)
    return {} if locator_service.nil?

    page_hint = source_locator&.dig("page_hint")
    section_hint = source_locator&.dig("section_hint")

    evidence_candidates(value).each do |candidate|
      result = locator_service.resolve(candidate, page_hint: page_hint, section_hint: section_hint)
      next if result[:locator].blank?

      return {
        source_excerpt: result[:locator]["matched_text"].presence || candidate,
        source_locator: result[:locator],
        source_match_strategy: result[:strategy]
      }
    end

    {}
  end

  def evidence_candidates(value)
    raw_candidates =
      case value
      when String
        [ value ]
      when Numeric
        normalized = format("%.2f", value.to_f)
        [ value.to_s, normalized, "$#{normalized}" ]
      when Hash
        value.values.flat_map { |nested| evidence_candidates(nested) }
      when Array
        value.flat_map { |nested| evidence_candidates(nested) }
      else
        []
      end

    raw_candidates
      .filter_map { |candidate| candidate.to_s.squish.presence }
      .select { |candidate| candidate.length >= 4 }
      .uniq
      .sort_by { |candidate| -candidate.length }
  end

  def build_documents_for_locator
    @contract.contract_documents
      .where(extraction_status: "completed")
      .order(:position)
      .map { |doc| { id: doc.id, name: doc.filename, text: doc.extracted_text } }
      .select { |d| d[:text].present? }
  end

  def default_confidence_threshold
    80
  end

  def serialize_escalation(esc)
    { "effective_date" => esc.effective_date&.to_s, "base_rent_monthly" => esc.base_rent_monthly&.to_f,
      "escalation_type" => esc.escalation_type, "escalation_value" => esc.escalation_value&.to_f }
  end

  def serialize_option(opt)
    { "option_type" => opt.option_type, "exercise_deadline" => opt.exercise_deadline&.to_s,
      "term_length_months" => opt.term_length_months }
  end

  def serialize_milestone(ms)
    { "milestone_type" => ms.milestone_type, "due_date" => ms.due_date&.to_s,
      "description" => ms.description }
  end

  def serialize_clause(clause)
    { "clause_type" => clause.clause_type, "content" => clause.content }
  end

  def enrich_lease_milestones_with_evidence(value, metadata, locator_service)
    ReviewMilestoneEvidenceBuilder.new(
      locator_service: locator_service,
      metadata: metadata
    ).call(value)
  end

  def enrich_key_clauses_with_evidence(value, metadata, locator_service)
    ReviewKeyClauseEvidenceBuilder.new(
      locator_service: locator_service,
      metadata: metadata
    ).call(value)
  end

  def milestone_evidence_present?(value)
    return false unless value.is_a?(Array)

    value.any? do |item|
      item.is_a?(Hash) && item["source_excerpt"].to_s.squish.present?
    end
  end

  def key_clause_evidence_present?(value)
    return false unless value.is_a?(Array)

    value.any? do |item|
      next false unless item.is_a?(Hash)

      item["source_excerpt"].to_s.squish.present? || item["source_locator"].is_a?(Hash)
    end
  end
end
