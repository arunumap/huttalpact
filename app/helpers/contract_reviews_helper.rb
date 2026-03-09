# frozen_string_literal: true

module ContractReviewsHelper
  MILESTONE_TYPE_LABELS = {
    "cam_reconciliation" => "CAM Reconciliation",
    "insurance_renewal" => "Insurance Renewal",
    "estoppel_response" => "Estoppel Response",
    "ti_completion" => "TI Completion",
    "percentage_rent_report" => "Percentage Rent Report",
    "guarantee_burnoff" => "Guarantee Burnoff",
    "custom" => "Custom Milestone"
  }.freeze

  MILESTONE_PURPOSES = {
    "cam_reconciliation" => "Tracks when CAM true-up or reconciliation support should be delivered.",
    "insurance_renewal" => "Tracks renewal proof deadlines for required insurance coverage.",
    "estoppel_response" => "Tracks response windows for estoppel certificate requests.",
    "ti_completion" => "Tracks completion timing for tenant improvement obligations.",
    "percentage_rent_report" => "Tracks reporting deadlines for percentage-rent sales statements.",
    "guarantee_burnoff" => "Tracks when guaranty release conditions should be reviewed."
  }.freeze

  KEY_CLAUSE_TYPE_LABELS = {
    "sla" => "SLA",
    "cam_provision" => "CAM Provision",
    "ada_compliance" => "ADA Compliance",
    "hazmat" => "HazMat",
    "subletting_assignment" => "Subletting & Assignment",
    "tenant_improvement" => "Tenant Improvement"
  }.freeze

  KEY_CLAUSE_PURPOSES = {
    "termination" => "Explains how and when either party can end the agreement.",
    "renewal" => "Defines if and how the agreement renews beyond the initial term.",
    "penalty" => "Describes fees or consequences for non-performance or late actions.",
    "sla" => "Defines expected service levels and remedies if standards are missed.",
    "price_escalation" => "Explains when and how pricing can increase over time.",
    "liability" => "Allocates responsibility for damages and legal exposure.",
    "insurance_requirement" => "Lists required insurance coverage and proof obligations.",
    "security_deposit" => "Explains deposit amount, usage, and return conditions.",
    "cam_provision" => "Defines responsibility for shared operating expense charges.",
    "maintenance_responsibility" => "Clarifies who handles repair and maintenance obligations.",
    "subletting_assignment" => "Defines whether rights can be assigned or sublet to another party.",
    "exclusivity" => "Specifies exclusivity rights or restrictions related to competing uses.",
    "co_tenancy" => "Defines obligations tied to occupancy of other tenants or anchors.",
    "parking" => "Covers parking rights, limits, and related costs.",
    "signage" => "Defines signage rights, approvals, and restrictions.",
    "hazmat" => "Covers hazardous materials restrictions and compliance obligations.",
    "ada_compliance" => "Defines accessibility compliance responsibilities.",
    "subordination" => "Explains lien priority and subordination requirements.",
    "use_restriction" => "Defines permitted and prohibited use of the premises or services.",
    "tenant_improvement" => "Defines build-out, allowance, and improvement responsibilities."
  }.freeze

  def format_review_value(field)
    parsed = parse_review_value(field.final_value)
    catalog_entry = ReviewFieldCatalog.find(field.field_name)
    return "—" if parsed.nil?

    case catalog_entry&.value_type
    when "currency"
      number_to_currency(parsed)
    when "date"
      parsed.is_a?(String) ? Date.parse(parsed).strftime("%B %d, %Y") : parsed
    when "boolean"
      parsed ? "Yes" : "No"
    when "enum"
      parsed.to_s.titleize.gsub("_", " ")
    when "array"
      "#{parsed.length} #{'item'.pluralize(parsed.length)}" if parsed.is_a?(Array)
    else
      parsed.to_s
    end
  rescue StandardError
    field.final_value.to_s
  end

  def parse_review_value(raw)
    return nil if raw.nil?

    JSON.parse(raw)
  rescue JSON::ParserError
    raw
  end

  def review_field_input_type(field)
    ReviewFieldCatalog.find(field.field_name)&.value_type || "string"
  end

  def review_field_enum_options(field)
    ReviewFieldCatalog.find(field.field_name)&.enum_options || []
  end

  def confidence_color_class(confidence)
    return "bg-gray-100 text-gray-600" if confidence.nil?

    if confidence >= 80
      "bg-green-100 text-green-800"
    elsif confidence >= 50
      "bg-amber-100 text-amber-800"
    else
      "bg-red-100 text-red-800"
    end
  end

  def status_badge_class(status)
    case status
    when "confirmed", "auto_accepted"
      "bg-green-100 text-green-700"
    when "edited"
      "bg-blue-100 text-blue-700"
    when "not_found"
      "bg-gray-100 text-gray-600"
    when "not_applicable"
      "bg-gray-100 text-gray-500"
    else
      "bg-amber-100 text-amber-700"
    end
  end

  def review_field_input(form, field)
    value_type = review_field_input_type(field)
    current_value = parse_review_value(field.extracted_value)

    case value_type
    when "date"
      form.date_field :user_value, value: current_value,
        class: "w-full rounded-md border-gray-300 text-sm shadow-sm focus:border-amber-500 focus:ring-amber-500"
    when "number"
      form.number_field :user_value, value: current_value, step: "any",
        class: "w-full rounded-md border-gray-300 text-sm shadow-sm focus:border-amber-500 focus:ring-amber-500"
    when "currency"
      form.number_field :user_value, value: current_value, step: "0.01",
        class: "w-full rounded-md border-gray-300 text-sm shadow-sm focus:border-amber-500 focus:ring-amber-500"
    when "boolean"
      form.select :user_value, [ [ "Yes", "true" ], [ "No", "false" ] ], { selected: current_value.to_s },
        class: "w-full rounded-md border-gray-300 text-sm shadow-sm focus:border-amber-500 focus:ring-amber-500"
    when "enum"
      options = review_field_enum_options(field).map { |o| [ o.titleize.tr("_", " "), o ] }
      form.select :user_value, options, { include_blank: "Select...", selected: current_value },
        class: "w-full rounded-md border-gray-300 text-sm shadow-sm focus:border-amber-500 focus:ring-amber-500"
    when "text"
      form.text_area :user_value, value: current_value, rows: 3,
        class: "w-full rounded-md border-gray-300 text-sm shadow-sm focus:border-amber-500 focus:ring-amber-500"
    else
      form.text_field :user_value, value: current_value,
        class: "w-full rounded-md border-gray-300 text-sm shadow-sm focus:border-amber-500 focus:ring-amber-500"
    end
  end

  def uncertainty_guidance_message(field)
    return nil unless field.needs_review?
    return nil if field.source_excerpt.present?

    value = format_review_value(field)
    confidence_text = uncertainty_confidence_text(field.confidence)
    best_guess_text = value == "—" ? "" : " Best guess: #{value}."

    "#{confidence_text}#{best_guess_text} Can you validate this against the document or edit it?"
  end

  def milestone_drawer_id(field)
    "#{dom_id(field)}_milestones_drawer"
  end

  def key_clause_drawer_id(field)
    "#{dom_id(field)}_key_clauses_drawer"
  end

  def milestone_items(field)
    value = parse_review_value(field.final_value)
    return [] unless value.is_a?(Array)

    value.filter_map do |item|
      next unless item.is_a?(Hash)

      normalized_item = item.stringify_keys
      normalized_item["source_locator"] = normalize_source_locator(normalized_item["source_locator"])

      if normalized_item["source_excerpt"].to_s.squish.blank? && field.source_excerpt.present?
        normalized_item["source_excerpt"] = field.source_excerpt
        normalized_item["source_locator"] ||= normalize_source_locator(field.source_locator)
        normalized_item["reasoning"] = normalized_item["reasoning"].presence || field.reasoning
        normalized_item["evidence_status"] = "broad"
      end

      normalized_item["source_excerpt"] = normalized_item["source_excerpt"].to_s.squish.presence
      normalized_item["reasoning"] = normalized_item["reasoning"].to_s.squish.presence
      normalized_item["evidence_status"] = normalized_item["evidence_status"].presence ||
        (normalized_item["source_excerpt"].present? ? "grounded" : "unresolved")
      normalized_item
    end
  end

  def key_clause_items(field)
    value = parse_review_value(field.final_value)
    return [] unless value.is_a?(Array)

    value.filter_map do |item|
      next unless item.is_a?(Hash)

      normalized_item = item.stringify_keys
      normalized_item["source_locator"] = normalize_source_locator(normalized_item["source_locator"])
      normalized_item["source_excerpt"] = normalized_item["source_excerpt"].to_s.squish.presence ||
        field.source_excerpt.to_s.squish.presence ||
        normalized_item["content"].to_s.squish.presence
      normalized_item["source_locator"] ||= normalize_source_locator(field.source_locator)
      normalized_item["reasoning"] = normalized_item["reasoning"].presence || field.reasoning
      normalized_item["evidence_status"] = "broad" if field.source_excerpt.present? && item["source_excerpt"].blank?

      normalized_item["reasoning"] = normalized_item["reasoning"].to_s.squish.presence
      normalized_item["evidence_status"] = normalized_item["evidence_status"].presence ||
        if normalized_item["source_locator"].present?
          "grounded"
        elsif normalized_item["source_excerpt"].present?
          "broad"
        else
          "unresolved"
        end
      normalized_item
    end
  end

  def milestone_type_label(type)
    MILESTONE_TYPE_LABELS[type.to_s] || type.to_s.humanize.titleize
  end

  def milestone_purpose_text(milestone)
    MILESTONE_PURPOSES[milestone["milestone_type"].to_s] || "Tracks a custom lease obligation or deadline."
  end

  def milestone_due_date_label(milestone)
    raw = milestone["due_date"].presence
    return "No due date provided" if raw.blank?

    Date.parse(raw).strftime("%B %d, %Y")
  rescue ArgumentError
    raw
  end

  def milestone_recurrence_label(milestone)
    recurring = ActiveModel::Type::Boolean.new.cast(milestone["recurring"])
    return "One-time milestone" unless recurring

    interval = milestone["recurrence_interval"].presence
    return "Recurring milestone" if interval.blank?

    "Repeats #{interval.humanize.downcase}"
  end

  def milestone_summary(milestone)
    "#{milestone_type_label(milestone['milestone_type'])} due #{milestone_due_date_label(milestone)}"
  end

  def milestone_source_excerpt(milestone)
    milestone["source_excerpt"].to_s.squish.presence
  end

  def milestone_source_locator(milestone)
    normalize_source_locator(milestone["source_locator"]) || {}
  end

  def milestone_reasoning(milestone)
    milestone["reasoning"].to_s.squish.presence
  end

  def milestone_evidence_status(milestone)
    milestone["evidence_status"].presence ||
      (milestone_source_excerpt(milestone).present? ? "grounded" : "unresolved")
  end

  def milestone_evidence_message(milestone)
    case milestone_evidence_status(milestone)
    when "grounded"
      "AI linked this milestone to a specific supporting excerpt."
    when "broad"
      "AI only found broader milestone evidence. Please validate this specific item."
    else
      "AI could not point to a supporting excerpt for this milestone. Edit or delete it before completing review."
    end
  end

  def milestone_type_options
    LeaseMilestone::MILESTONE_TYPES.map { |type| [ milestone_type_label(type), type ] }
  end

  def milestone_recurrence_options
    LeaseMilestone::RECURRENCE_INTERVALS.map { |interval| [ interval.titleize, interval ] }
  end

  def key_clause_type_label(type)
    type_key = type.to_s
    return KEY_CLAUSE_TYPE_LABELS[type_key] if KEY_CLAUSE_TYPE_LABELS.key?(type_key)

    type_key.humanize.titleize
  end

  def key_clause_purpose_text(key_clause)
    KEY_CLAUSE_PURPOSES[key_clause["clause_type"].to_s] || "Captures a material legal clause for contract obligations."
  end

  def key_clause_summary(key_clause)
    "#{key_clause_type_label(key_clause['clause_type'])}: #{truncate(key_clause['content'].to_s, length: 110)}"
  end

  def key_clause_source_excerpt(key_clause)
    key_clause["source_excerpt"].to_s.squish.presence
  end

  def key_clause_source_locator(key_clause)
    normalize_source_locator(key_clause["source_locator"]) || {}
  end

  def key_clause_reasoning(key_clause)
    key_clause["reasoning"].to_s.squish.presence
  end

  def key_clause_evidence_status(key_clause)
    key_clause["evidence_status"].presence ||
      if key_clause_source_locator(key_clause).present?
        "grounded"
      elsif key_clause_source_excerpt(key_clause).present?
        "broad"
      else
        "unresolved"
      end
  end

  def key_clause_evidence_message(key_clause)
    case key_clause_evidence_status(key_clause)
    when "grounded"
      "AI linked this clause to a specific supporting excerpt."
    when "broad"
      "AI found supporting clause language, but this item still needs a quick human validation."
    else
      "AI could not point to a supporting excerpt for this clause. Edit or delete it before completing review."
    end
  end

  def key_clause_type_options
    KeyClause::CLAUSE_TYPES.map { |type| [ key_clause_type_label(type), type ] }
  end

  def key_clause_confidence_label(key_clause)
    score = Integer(key_clause["confidence_score"], exception: false)
    return "Not provided" if score.nil?

    "#{score.clamp(0, 100)}%"
  end

  def progress_bar_color_class(percentage)
    if percentage >= 80
      "bg-green-500"
    elsif percentage >= 40
      "bg-amber-500"
    else
      "bg-red-400"
    end
  end

  private

  def normalize_source_locator(locator)
    return nil unless locator.is_a?(Hash)

    locator.stringify_keys.slice("document_id", "start_offset", "end_offset", "matched_text")
  end

  alias_method :normalize_milestone_locator, :normalize_source_locator

  def uncertainty_confidence_text(confidence)
    return "I couldn't find a direct quote for this value." if confidence.nil?

    if confidence < 50
      "Confidence is low and I couldn't find a direct quote for this value."
    elsif confidence < 80
      "Confidence is moderate, but I couldn't find a direct quote for this value."
    else
      "Confidence is below the review threshold because I couldn't find a direct quote for this value."
    end
  end
end
