# frozen_string_literal: true

class ReviewKeyClauseArrayEditor
  class InvalidKeyClausesError < StandardError; end
  class InvalidKeyClauseIndexError < StandardError; end

  EVIDENCE_STATUSES = %w[grounded broad unresolved].freeze

  def initialize(raw_value)
    @raw_value = raw_value
  end

  def update(index:, attrs:)
    items = key_clauses.deep_dup
    existing = items[index]
    raise InvalidKeyClauseIndexError, "Key clause could not be found." unless existing

    updated = normalize_key_clause(existing.merge(attrs.to_h))
    validate!(updated)
    items[index] = updated
    items
  end

  def remove(index:)
    items = key_clauses.deep_dup
    removed = items.delete_at(index)
    raise InvalidKeyClauseIndexError, "Key clause could not be found." unless removed

    items
  end

  private

  def key_clauses
    @key_clauses ||= begin
      parsed = JSON.parse(@raw_value.presence || "[]")
      raise InvalidKeyClausesError, "Key clauses data is invalid." unless parsed.is_a?(Array)

      parsed.map { |item| normalize_key_clause(item) }
    rescue JSON::ParserError
      raise InvalidKeyClausesError, "Key clauses data is invalid."
    end
  end

  def normalize_key_clause(raw_clause)
    clause = raw_clause.to_h.stringify_keys
    source_excerpt = clause["source_excerpt"].to_s.squish.presence

    {
      "clause_type" => clause["clause_type"].to_s,
      "content" => clause["content"].to_s.strip.presence,
      "page_reference" => clause["page_reference"].to_s.squish.presence,
      "confidence_score" => normalize_confidence_score(clause["confidence_score"]),
      "source_document" => clause["source_document"].to_s.squish.presence,
      "source_excerpt" => source_excerpt,
      "source_locator" => normalize_locator(clause["source_locator"]),
      "source_match_strategy" => clause["source_match_strategy"].presence,
      "reasoning" => clause["reasoning"].to_s.squish.presence,
      "evidence_status" => normalize_evidence_status(clause["evidence_status"], source_excerpt)
    }
  end

  def validate!(clause)
    unless KeyClause::CLAUSE_TYPES.include?(clause["clause_type"])
      raise InvalidKeyClausesError, "Clause type is invalid."
    end

    raise InvalidKeyClausesError, "Clause content is required." if clause["content"].blank?

    score = clause["confidence_score"]
    return if score.nil? || (score.is_a?(Integer) && score.between?(0, 100))

    raise InvalidKeyClausesError, "Confidence score must be between 0 and 100."
  end

  def normalize_confidence_score(raw_score)
    return nil if raw_score.blank?

    Integer(raw_score, exception: false)
  end

  def normalize_locator(locator)
    return nil unless locator.is_a?(Hash)

    locator.stringify_keys.slice("document_id", "start_offset", "end_offset", "matched_text")
  end

  def normalize_evidence_status(raw_status, source_excerpt)
    status = raw_status.to_s.presence
    return status if EVIDENCE_STATUSES.include?(status)

    source_excerpt.present? ? "grounded" : "unresolved"
  end
end
