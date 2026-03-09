class ReviewLearningIngestionService
  CORRECTED_DECISIONS = %w[edited not_found not_applicable].freeze
  SOURCE_LOCATOR_KEYS = %w[document_id start_offset end_offset matched_text page_hint section_hint].freeze
  EVIDENCE_QUALITY_MAP = {
    "grounded" => { quality: "strong", score: 95 },
    "broad" => { quality: "moderate", score: 75 },
    "unresolved" => { quality: "weak", score: 40 },
    "missing" => { quality: "missing", score: nil }
  }.freeze

  def initialize(review:)
    @review = review
    @contract = review.contract
  end

  def call
    reviewed_fields.find_each do |field|
      event = ReviewLearningEvent.find_or_initialize_by(contract_review_field: field)
      event.assign_attributes(event_attributes_for(field))
      event.save!
    end

    enqueue_aggregate_refreshes!
  end

  private

  def reviewed_fields
    @review.fields.reviewed.includes(:reviewed_by, :source_document)
  end

  def event_attributes_for(field)
    evidence = evidence_context_for(field)

    {
      organization: @review.organization,
      contract: @contract,
      contract_review: @review,
      contract_review_field: field,
      reviewed_by: field.reviewed_by || @review.completed_by,
      source_document: field.source_document,
      ai_usage_log: ai_usage_log,
      review_type: @review.review_type,
      contract_type: @contract.contract_type.presence || "unknown",
      field_name: field.field_name,
      field_group: field.field_group,
      decision: field.status,
      confidence: field.confidence,
      confidence_threshold: @review.confidence_threshold,
      needs_review: field.needs_review,
      corrected: corrected_decision?(field.status),
      extracted_value: field.extracted_value,
      final_value: field.final_value,
      user_value: field.user_value,
      source_excerpt: field.source_excerpt,
      source_match_strategy: field.source_match_strategy,
      source_excerpt_present: evidence[:source_excerpt_present],
      source_locator: evidence[:source_locator],
      evidence_quality: evidence[:evidence_quality],
      evidence_quality_score: evidence[:evidence_quality_score],
      field_metadata: field_metadata_for(field, evidence),
      review_metadata: review_metadata_for(field, evidence),
      reviewed_at: field.reviewed_at || @review.completed_at || Time.current
    }
  end

  def field_metadata_for(field, evidence)
    field_definition = ReviewFieldCatalog.find(field.field_name)

    {
      "display_name" => field.display_name,
      "field_type" => field_definition&.value_type || "unknown",
      "field_position" => field.position,
      "lease_only" => field_definition&.lease_only,
      "source_locator_present" => evidence[:source_locator_present],
      "item_source_locator_count" => evidence[:item_source_locator_count],
      "evidence_status" => evidence[:evidence_status]
    }.compact
  end

  def review_metadata_for(field, evidence)
    {
      "review_status" => @review.status,
      "review_completed_at" => @review.completed_at&.iso8601,
      "review_completed_by_id" => @review.completed_by_id,
      "completion_context_key" => completion_context_key,
      "reviewed_fields_count" => @review.reviewed_fields,
      "total_fields_count" => @review.total_fields,
      "correctness_signal" => corrected_decision?(field.status) ? "corrected" : "accepted",
      "correction_type" => corrected_decision?(field.status) ? field.status : "none",
      "item_evidence_statuses" => evidence[:item_evidence_statuses]
    }.compact
  end

  def completion_context_key
    "#{@review.id}:#{@review.completed_at&.to_i || @review.updated_at.to_i}"
  end

  def corrected_decision?(decision)
    CORRECTED_DECISIONS.include?(decision)
  end

  def evidence_context_for(field)
    item_evidence = item_evidence_for(field)
    source_locator = normalize_source_locator(field.source_locator) || item_evidence[:first_locator] || {}

    source_locator_present = source_locator.present? || item_evidence[:source_locator_count].positive?
    source_excerpt_present = field.source_excerpt.to_s.squish.present? || item_evidence[:source_excerpt_count].positive?
    evidence_status = evidence_status_for(
      source_locator_present: source_locator_present,
      source_excerpt_present: source_excerpt_present,
      item_statuses: item_evidence[:statuses]
    )
    quality = EVIDENCE_QUALITY_MAP.fetch(evidence_status)

    {
      source_locator: source_locator,
      source_locator_present: source_locator_present,
      source_excerpt_present: source_excerpt_present,
      evidence_status: evidence_status,
      evidence_quality: quality[:quality],
      evidence_quality_score: quality[:score],
      item_source_locator_count: item_evidence[:source_locator_count],
      item_evidence_statuses: item_evidence[:statuses]
    }
  end

  def evidence_status_for(source_locator_present:, source_excerpt_present:, item_statuses:)
    return "grounded" if source_locator_present || item_statuses.include?("grounded")
    return "broad" if source_excerpt_present || item_statuses.include?("broad")
    return "unresolved" if item_statuses.include?("unresolved")

    "missing"
  end

  def item_evidence_for(field)
    statuses = []
    source_locators = []
    source_excerpt_count = 0

    parsed_item_payloads(field).each do |item|
      next unless item.is_a?(Hash)

      normalized_item = item.stringify_keys
      statuses << normalized_item["evidence_status"] if normalized_item["evidence_status"].present?

      source_locator = normalize_source_locator(normalized_item["source_locator"])
      source_locators << source_locator if source_locator.present?
      source_excerpt_count += 1 if normalized_item["source_excerpt"].to_s.squish.present?
    end

    {
      statuses: statuses.uniq,
      source_locator_count: source_locators.count,
      source_excerpt_count: source_excerpt_count,
      first_locator: source_locators.first
    }
  end

  def parsed_item_payloads(field)
    [ field.final_value, field.user_value, field.extracted_value ]
      .filter_map { |raw| parse_json(raw) }
      .flat_map do |parsed|
        case parsed
        when Array
          parsed
        when Hash
          [ parsed ]
        else
          []
        end
      end
  end

  def parse_json(raw_value)
    return nil if raw_value.blank?

    JSON.parse(raw_value)
  rescue JSON::ParserError
    nil
  end

  def normalize_source_locator(locator)
    return nil unless locator.is_a?(Hash)

    locator.stringify_keys.slice(*SOURCE_LOCATOR_KEYS).presence
  end

  def ai_usage_log
    @ai_usage_log ||= begin
      logs = @contract.ai_usage_logs.successful.where(extraction_mode: @review.review_type)
      logs.where("created_at <= ?", @review.created_at).order(created_at: :desc).first || logs.order(created_at: :desc).first
    end
  end

  def enqueue_aggregate_refreshes!
    reviewed_dates_for_aggregation.each do |reviewed_on|
      RefreshReviewLearningAggregatesJob.perform_later(@review.organization_id, reviewed_on.iso8601)
    end
  end

  def reviewed_dates_for_aggregation
    ReviewLearningEvent
      .where(contract_review: @review)
      .distinct
      .pluck(Arel.sql("DATE(reviewed_at)"))
      .compact
      .map(&:to_date)
      .uniq
      .sort
  end
end
