# frozen_string_literal: true

class ReviewKeyClauseEvidenceBuilder
  EVIDENCE_STATUSES = %w[grounded broad unresolved].freeze

  def initialize(locator_service:, metadata: {})
    @locator_service = locator_service
    @metadata = metadata.to_h.stringify_keys
  end

  def call(key_clauses)
    return [] unless key_clauses.is_a?(Array)

    key_clauses.filter_map do |key_clause|
      next unless key_clause.is_a?(Hash)

      build_key_clause_with_evidence(key_clause.stringify_keys)
    end
  end

  private

  def build_key_clause_with_evidence(key_clause)
    normalized = normalize_key_clause(key_clause)
    page_hint = page_hint_from(key_clause["page_reference"])
    section_hint = section_hint_from(key_clause["page_reference"])

    item_excerpt = key_clause["source_excerpt"].to_s.squish.presence || normalized["content"]
    item_reasoning = key_clause["reasoning"].to_s.squish.presence
    item_locator = normalize_locator(key_clause["source_locator"])

    item_result = resolve_from_item_excerpt(item_excerpt, page_hint:, section_hint:)
    item_result ||= resolve_from_candidates(clause_evidence_candidates(normalized), page_hint:, section_hint:)
    fallback_result = fallback_evidence

    if item_result&.dig(:source_locator).present?
      evidence_status = "grounded"
      excerpt = item_result[:source_excerpt]
      locator = item_result[:source_locator]
      match_strategy = item_result[:source_match_strategy]
    elsif fallback_result.present?
      evidence_status = "broad"
      excerpt = fallback_result[:source_excerpt]
      locator = fallback_result[:source_locator]
      match_strategy = fallback_result[:source_match_strategy]
    else
      evidence_status = "unresolved"
      excerpt = item_result&.dig(:source_excerpt) || item_excerpt
      locator = item_locator
      match_strategy = item_result&.dig(:source_match_strategy)
    end

    normalized.merge(
      "source_excerpt" => excerpt,
      "reasoning" => item_reasoning || fallback_reasoning,
      "source_locator" => locator,
      "source_match_strategy" => match_strategy,
      "evidence_status" => normalize_evidence_status(evidence_status, excerpt, locator)
    )
  end

  def resolve_from_item_excerpt(excerpt, page_hint:, section_hint:)
    return nil if excerpt.blank?

    resolve_excerpt(excerpt, page_hint:, section_hint:)
  end

  def resolve_from_candidates(candidates, page_hint:, section_hint:)
    candidates.each do |candidate|
      result = resolve_excerpt(candidate, page_hint:, section_hint:)
      return result if result.present?
    end
    nil
  end

  def resolve_excerpt(excerpt, page_hint:, section_hint:)
    return nil if excerpt.blank?
    return unresolved_result(excerpt) if @locator_service.nil?

    result = @locator_service.resolve(excerpt, page_hint:, section_hint:)
    locator = normalize_locator(result[:locator])
    return unresolved_result(excerpt) if locator.blank?

    {
      source_excerpt: locator["matched_text"].presence || excerpt,
      source_locator: locator,
      source_match_strategy: result[:strategy]
    }
  end

  def unresolved_result(excerpt)
    {
      source_excerpt: excerpt,
      source_locator: nil,
      source_match_strategy: nil
    }
  end

  def fallback_evidence
    @fallback_evidence ||= begin
      fallback_excerpt = @metadata["source_excerpt"].to_s.squish.presence
      if fallback_excerpt.present?
        resolve_excerpt(
          fallback_excerpt,
          page_hint: @metadata["page_hint"],
          section_hint: @metadata["section_hint"]
        ) || unresolved_result(fallback_excerpt)
      end
    end
  end

  def fallback_reasoning
    @metadata["reasoning"].to_s.squish.presence
  end

  def normalize_key_clause(key_clause)
    {
      "clause_type" => key_clause["clause_type"].to_s,
      "content" => key_clause["content"].to_s.strip.presence,
      "page_reference" => key_clause["page_reference"].to_s.squish.presence,
      "confidence_score" => normalize_confidence_score(key_clause["confidence_score"]),
      "source_document" => key_clause["source_document"].to_s.squish.presence
    }
  end

  def clause_evidence_candidates(key_clause)
    candidates = []
    candidates << key_clause["content"]
    candidates << key_clause["page_reference"]
    candidates << key_clause["clause_type"].to_s.humanize
    candidates << "#{key_clause['clause_type'].to_s.humanize} #{key_clause['content']}".squish

    candidates
      .filter_map { |candidate| candidate.to_s.squish.presence }
      .select { |candidate| candidate.length >= 4 }
      .uniq
  end

  def normalize_confidence_score(raw_score)
    return nil if raw_score.blank?

    score = Integer(raw_score, exception: false)
    return nil if score.nil?

    score.clamp(0, 100)
  end

  def normalize_locator(locator)
    return nil unless locator.is_a?(Hash)

    locator.stringify_keys.slice("document_id", "start_offset", "end_offset", "matched_text")
  end

  def normalize_evidence_status(status, excerpt, locator)
    return status if EVIDENCE_STATUSES.include?(status)
    return "grounded" if locator.present? && excerpt.present?
    return "broad" if excerpt.present?

    "unresolved"
  end

  def page_hint_from(page_reference)
    text = page_reference.to_s
    return nil if text.blank?

    page_match = text.match(/page\s*(\d+)/i) || text.match(/\b(\d+)\b/)
    page_match && page_match[1].to_i
  end

  def section_hint_from(page_reference)
    text = page_reference.to_s.squish
    return nil if text.blank?
    return text if text.match?(/section|article/i)

    nil
  end
end
