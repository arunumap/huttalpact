# frozen_string_literal: true

class ReviewMilestoneArrayEditor
  class InvalidMilestonesError < StandardError; end
  class InvalidMilestoneIndexError < StandardError; end

  def initialize(raw_value)
    @raw_value = raw_value
  end

  def update(index:, attrs:)
    items = milestones.deep_dup
    existing = items[index]
    raise InvalidMilestoneIndexError, "Milestone could not be found." unless existing

    updated = normalize_milestone(existing.merge(attrs.to_h))
    validate!(updated)
    items[index] = updated
    items
  end

  def remove(index:)
    items = milestones.deep_dup
    removed = items.delete_at(index)
    raise InvalidMilestoneIndexError, "Milestone could not be found." unless removed

    items
  end

  private

  def milestones
    @milestones ||= begin
      parsed = JSON.parse(@raw_value.presence || "[]")
      raise InvalidMilestonesError, "Milestones data is invalid." unless parsed.is_a?(Array)

      parsed.map { |milestone| normalize_milestone(milestone) }
    rescue JSON::ParserError
      raise InvalidMilestonesError, "Milestones data is invalid."
    end
  end

  def normalize_milestone(milestone)
    data = milestone.to_h.stringify_keys
    recurring = ActiveModel::Type::Boolean.new.cast(data["recurring"])
    locator = normalize_locator(data["source_locator"])
    source_excerpt = data["source_excerpt"].to_s.squish.presence

    {
      "milestone_type" => data["milestone_type"].to_s,
      "due_date" => data["due_date"].presence,
      "description" => data["description"].to_s.strip.presence,
      "recurring" => recurring,
      "recurrence_interval" => recurring ? data["recurrence_interval"].presence : nil,
      "source_excerpt" => source_excerpt,
      "source_locator" => locator,
      "source_match_strategy" => data["source_match_strategy"].presence,
      "reasoning" => data["reasoning"].to_s.squish.presence,
      "evidence_status" => data["evidence_status"].presence || (source_excerpt.present? ? "grounded" : "unresolved")
    }
  end

  def validate!(milestone)
    unless LeaseMilestone::MILESTONE_TYPES.include?(milestone["milestone_type"])
      raise InvalidMilestonesError, "Milestone type is invalid."
    end

    raise InvalidMilestonesError, "Due date is required." if milestone["due_date"].blank?

    begin
      Date.iso8601(milestone["due_date"])
    rescue ArgumentError
      raise InvalidMilestonesError, "Due date is invalid."
    end

    interval = milestone["recurrence_interval"]
    return if interval.blank? || LeaseMilestone::RECURRENCE_INTERVALS.include?(interval)

    raise InvalidMilestonesError, "Recurrence interval is invalid."
  end

  def normalize_locator(locator)
    return nil unless locator.is_a?(Hash)

    locator.stringify_keys.slice("document_id", "start_offset", "end_offset", "matched_text")
  end
end
