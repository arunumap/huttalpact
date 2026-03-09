# frozen_string_literal: true

class ReviewMilestoneEvidenceBuilder
  def initialize(locator_service:, metadata: {})
    @locator_service = locator_service
    @metadata = metadata.to_h.stringify_keys
  end

  def call(milestones)
    return [] unless milestones.is_a?(Array)

    milestones.filter_map do |milestone|
      next unless milestone.is_a?(Hash)

      build_milestone_with_evidence(milestone.stringify_keys)
    end
  end

  private

  def build_milestone_with_evidence(milestone)
    normalized = normalize_milestone(milestone)

    item_excerpt = milestone["source_excerpt"].to_s.squish.presence
    item_reasoning = milestone["reasoning"].to_s.squish.presence
    item_locator = normalize_locator(milestone["source_locator"])

    item_result = resolve_from_item_excerpt(item_excerpt)
    item_result ||= resolve_from_candidates(milestone_evidence_candidates(normalized))
    fallback_result = fallback_evidence

    if item_result
      evidence_status = "grounded"
      excerpt = item_result[:source_excerpt]
      locator = item_result[:source_locator]
      match_strategy = item_result[:source_match_strategy]
    elsif fallback_result
      evidence_status = "broad"
      excerpt = fallback_result[:source_excerpt]
      locator = fallback_result[:source_locator]
      match_strategy = fallback_result[:source_match_strategy]
    else
      evidence_status = "unresolved"
      excerpt = item_excerpt
      locator = item_locator
      match_strategy = nil
    end

    normalized.merge(
      "source_excerpt" => excerpt,
      "reasoning" => item_reasoning || fallback_reasoning,
      "source_locator" => locator,
      "source_match_strategy" => match_strategy,
      "evidence_status" => evidence_status
    )
  end

  def resolve_from_item_excerpt(excerpt)
    return nil if excerpt.blank?

    resolve_excerpt(excerpt)
  end

  def resolve_from_candidates(candidates)
    return nil if @locator_service.nil?

    candidates.each do |candidate|
      result = resolve_excerpt(candidate)
      return result if result.present?
    end
    nil
  end

  def resolve_excerpt(excerpt)
    return nil if excerpt.blank?
    return unresolved_result(excerpt) if @locator_service.nil?

    result = @locator_service.resolve(excerpt, page_hint: page_hint, section_hint: section_hint)
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
      resolve_excerpt(fallback_excerpt) if fallback_excerpt.present?
    end
  end

  def fallback_reasoning
    @metadata["reasoning"].to_s.squish.presence
  end

  def page_hint
    @metadata["page_hint"]
  end

  def section_hint
    @metadata["section_hint"]
  end

  def normalize_milestone(milestone)
    recurring = ActiveModel::Type::Boolean.new.cast(milestone["recurring"])

    {
      "milestone_type" => milestone["milestone_type"].to_s,
      "due_date" => milestone["due_date"].presence,
      "description" => milestone["description"].to_s.strip.presence,
      "recurring" => recurring,
      "recurrence_interval" => recurring ? milestone["recurrence_interval"].presence : nil
    }
  end

  def normalize_locator(locator)
    return nil unless locator.is_a?(Hash)

    locator.stringify_keys.slice("document_id", "start_offset", "end_offset", "matched_text")
  end

  def milestone_evidence_candidates(milestone)
    candidates = []
    candidates << milestone["description"]
    candidates.concat(due_date_candidates(milestone["due_date"]))
    candidates << milestone["milestone_type"].to_s.humanize
    candidates << "#{milestone['milestone_type'].to_s.humanize} #{milestone['due_date']}".squish

    candidates
      .filter_map { |candidate| candidate.to_s.squish.presence }
      .select { |candidate| candidate.length >= 4 }
      .uniq
  end

  def due_date_candidates(raw_due_date)
    return [] if raw_due_date.blank?

    date = Date.parse(raw_due_date.to_s)
    [
      raw_due_date.to_s,
      date.iso8601,
      date.strftime("%B %-d, %Y"),
      date.strftime("%B %d, %Y")
    ]
  rescue Date::Error, ArgumentError
    [ raw_due_date.to_s ]
  end
end
