# frozen_string_literal: true

module ContractReviewsHelper
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
