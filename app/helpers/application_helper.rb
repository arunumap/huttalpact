module ApplicationHelper
  include Pagy::Frontend

  def sidebar_link_to(text, path, icon: nil)
    active = current_page?(path)
    base_classes = "group flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium"
    active_classes = active ? "bg-gray-800 text-white" : "text-gray-300 hover:bg-gray-800 hover:text-white"

    link_to path, class: "#{base_classes} #{active_classes}" do
      concat(sidebar_icon(icon, active:)) if icon
      concat(text)
    end
  end

  def contract_status_badge(status)
    colors = {
      "active"        => "bg-green-50 text-green-700 ring-green-600/20",
      "in_review"     => "bg-orange-50 text-orange-700 ring-orange-600/20",
      "expiring_soon" => "bg-amber-50 text-amber-700 ring-amber-600/20",
      "expired"       => "bg-red-50 text-red-700 ring-red-600/20",
      "renewed"       => "bg-blue-50 text-blue-700 ring-blue-600/20",
      "cancelled"     => "bg-gray-50 text-gray-600 ring-gray-500/20",
      "archived"      => "bg-purple-50 text-purple-700 ring-purple-600/20"
    }
    color_class = colors[status] || colors["active"]
    label = status.titleize.gsub("_", " ")

    tag.span(label, class: "inline-flex items-center rounded-full px-2 py-1 text-xs font-medium ring-1 ring-inset #{color_class}")
  end

  def contract_type_badge(contract_type)
    return "" if contract_type.blank?
    label = contract_type.titleize.gsub("_", " ")
    tag.span(label, class: "inline-flex items-center rounded-full bg-gray-100 px-2 py-1 text-xs font-medium text-gray-600")
  end

  def direction_badge(direction)
    if direction == "inbound"
      tag.span("Revenue", class: "inline-flex items-center rounded-full bg-emerald-50 px-2 py-1 text-xs font-medium text-emerald-700 ring-1 ring-inset ring-emerald-600/20")
    else
      tag.span("Expense", class: "inline-flex items-center rounded-full bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-600/20")
    end
  end

  def format_currency(amount)
    return "—" if amount.blank?
    number_to_currency(amount)
  end

  def format_date(date)
    return "—" if date.blank?
    date.strftime("%b %d, %Y")
  end

  def format_sqft(value)
    return "—" if value.blank?
    "#{number_with_delimiter(value.to_i)} SF"
  end

  def lease_type_badge(lease_type)
    colors = {
      "gross"          => "bg-green-50 text-green-700 ring-green-600/20",
      "modified_gross" => "bg-teal-50 text-teal-700 ring-teal-600/20",
      "nnn"            => "bg-blue-50 text-blue-700 ring-blue-600/20",
      "percentage"     => "bg-purple-50 text-purple-700 ring-purple-600/20"
    }
    labels = { "nnn" => "NNN (Triple Net)", "modified_gross" => "Modified Gross" }
    color_class = colors[lease_type] || "bg-gray-50 text-gray-600 ring-gray-500/20"
    label = labels[lease_type] || lease_type&.titleize || "Unknown"
    tag.span(label, class: "inline-flex items-center rounded-full px-2 py-1 text-xs font-medium ring-1 ring-inset #{color_class}")
  end

  def option_type_badge(option_type)
    colors = {
      "renewal"     => "bg-blue-50 text-blue-700 ring-blue-600/20",
      "expansion"   => "bg-green-50 text-green-700 ring-green-600/20",
      "termination" => "bg-red-50 text-red-700 ring-red-600/20",
      "purchase"    => "bg-purple-50 text-purple-700 ring-purple-600/20",
      "rofr"        => "bg-amber-50 text-amber-700 ring-amber-600/20",
      "rofo"        => "bg-orange-50 text-orange-700 ring-orange-600/20"
    }
    labels = { "rofr" => "Right of First Refusal", "rofo" => "Right of First Offer" }
    color_class = colors[option_type] || "bg-gray-50 text-gray-600 ring-gray-500/20"
    label = labels[option_type] || option_type&.titleize || "Unknown"
    tag.span(label, class: "inline-flex items-center rounded-full px-2 py-1 text-xs font-medium ring-1 ring-inset #{color_class}")
  end

  def escalation_type_badge(escalation_type)
    colors = {
      "fixed_percentage" => "bg-amber-50 text-amber-700 ring-amber-600/20",
      "cpi"              => "bg-blue-50 text-blue-700 ring-blue-600/20",
      "fmv_reset"        => "bg-purple-50 text-purple-700 ring-purple-600/20",
      "stepped"          => "bg-green-50 text-green-700 ring-green-600/20",
      "flat"             => "bg-gray-50 text-gray-600 ring-gray-500/20"
    }
    labels = { "cpi" => "CPI", "fmv_reset" => "FMV Reset", "fixed_percentage" => "Fixed %" }
    color_class = colors[escalation_type] || "bg-gray-50 text-gray-600 ring-gray-500/20"
    label = labels[escalation_type] || escalation_type&.titleize || "Unknown"
    tag.span(label, class: "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset #{color_class}")
  end

  def milestone_type_badge(milestone_type)
    colors = {
      "cam_reconciliation"     => "bg-teal-50 text-teal-700 ring-teal-600/20",
      "insurance_renewal"      => "bg-cyan-50 text-cyan-700 ring-cyan-600/20",
      "estoppel_response"      => "bg-amber-50 text-amber-700 ring-amber-600/20",
      "ti_completion"          => "bg-green-50 text-green-700 ring-green-600/20",
      "percentage_rent_report" => "bg-purple-50 text-purple-700 ring-purple-600/20",
      "guarantee_burnoff"      => "bg-rose-50 text-rose-700 ring-rose-600/20",
      "custom"                 => "bg-gray-50 text-gray-600 ring-gray-500/20"
    }
    color_class = colors[milestone_type] || "bg-gray-50 text-gray-600 ring-gray-500/20"
    label = milestone_type&.titleize&.gsub("_", " ") || "Unknown"
    tag.span(label, class: "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset #{color_class}")
  end

  def role_badge(role)
    colors = {
      "owner"  => "bg-purple-50 text-purple-700 ring-purple-600/20",
      "admin"  => "bg-blue-50 text-blue-700 ring-blue-600/20",
      "member" => "bg-gray-50 text-gray-600 ring-gray-500/20"
    }
    color_class = colors[role] || colors["member"]
    label = role.titleize
    tag.span(label, class: "inline-flex items-center rounded-full px-2 py-1 text-xs font-medium ring-1 ring-inset #{color_class}")
  end

  def clause_type_badge(clause_type)
    colors = {
      "termination"              => "bg-red-50 text-red-700 ring-red-600/20",
      "renewal"                  => "bg-blue-50 text-blue-700 ring-blue-600/20",
      "penalty"                  => "bg-orange-50 text-orange-700 ring-orange-600/20",
      "sla"                      => "bg-purple-50 text-purple-700 ring-purple-600/20",
      "price_escalation"         => "bg-amber-50 text-amber-700 ring-amber-600/20",
      "liability"                => "bg-rose-50 text-rose-700 ring-rose-600/20",
      "insurance_requirement"    => "bg-cyan-50 text-cyan-700 ring-cyan-600/20",
      "security_deposit"         => "bg-emerald-50 text-emerald-700 ring-emerald-600/20",
      "cam_provision"            => "bg-teal-50 text-teal-700 ring-teal-600/20",
      "maintenance_responsibility" => "bg-slate-50 text-slate-700 ring-slate-600/20",
      "subletting_assignment"    => "bg-indigo-50 text-indigo-700 ring-indigo-600/20",
      "exclusivity"              => "bg-fuchsia-50 text-fuchsia-700 ring-fuchsia-600/20",
      "co_tenancy"               => "bg-violet-50 text-violet-700 ring-violet-600/20",
      "parking"                  => "bg-sky-50 text-sky-700 ring-sky-600/20",
      "signage"                  => "bg-lime-50 text-lime-700 ring-lime-600/20",
      "hazmat"                   => "bg-red-50 text-red-700 ring-red-600/20",
      "ada_compliance"           => "bg-blue-50 text-blue-700 ring-blue-600/20",
      "subordination"            => "bg-zinc-50 text-zinc-700 ring-zinc-600/20",
      "use_restriction"          => "bg-amber-50 text-amber-700 ring-amber-600/20",
      "tenant_improvement"       => "bg-green-50 text-green-700 ring-green-600/20"
    }
    color_class = colors[clause_type] || "bg-gray-50 text-gray-600 ring-gray-500/20"
    label = clause_type.titleize.gsub("_", " ")
    tag.span(label, class: "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset #{color_class}")
  end

  def confidence_badge(score)
    if score >= 80
      color = "bg-green-50 text-green-700"
    elsif score >= 50
      color = "bg-amber-50 text-amber-700"
    else
      color = "bg-red-50 text-red-700"
    end
    tag.span("#{score}%", class: "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium #{color}")
  end

  def alert_type_badge(alert_type)
    colors = {
      "renewal_upcoming"          => "bg-blue-50 text-blue-700 ring-blue-600/20",
      "expiry_warning"            => "bg-amber-50 text-amber-700 ring-amber-600/20",
      "notice_period_start"       => "bg-purple-50 text-purple-700 ring-purple-600/20",
      "option_exercise_deadline"  => "bg-red-50 text-red-700 ring-red-600/20",
      "rent_escalation_date"      => "bg-emerald-50 text-emerald-700 ring-emerald-600/20",
      "cam_reconciliation"        => "bg-teal-50 text-teal-700 ring-teal-600/20",
      "ti_deadline"               => "bg-orange-50 text-orange-700 ring-orange-600/20",
      "milestone_reminder"        => "bg-indigo-50 text-indigo-700 ring-indigo-600/20"
    }
    color_class = colors[alert_type] || "bg-gray-50 text-gray-600 ring-gray-500/20"
    label = alert_type.titleize.gsub("_", " ")
    tag.span(label, class: "inline-flex items-center rounded-full px-2 py-1 text-xs font-medium ring-1 ring-inset #{color_class}")
  end

  def alert_status_badge(status)
    colors = {
      "pending"      => "bg-yellow-50 text-yellow-700 ring-yellow-600/20",
      "sent"         => "bg-blue-50 text-blue-700 ring-blue-600/20",
      "acknowledged" => "bg-green-50 text-green-700 ring-green-600/20",
      "snoozed"      => "bg-gray-50 text-gray-600 ring-gray-500/20"
    }
    color_class = colors[status] || "bg-gray-50 text-gray-600 ring-gray-500/20"
    label = status.titleize
    tag.span(label, class: "inline-flex items-center rounded-full px-2 py-1 text-xs font-medium ring-1 ring-inset #{color_class}")
  end

  def alert_urgency_label(alert, alert_preference: nil)
    overdue = alert_preference.present? ? alert.overdue_for_preference?(alert_preference) : alert.overdue?
    due_today = alert_preference.present? ? alert.due_today_for_preference?(alert_preference) : alert.due_today?

    if overdue
      tag.span("Overdue", class: "inline-flex items-center rounded-full bg-red-100 px-2 py-0.5 text-xs font-semibold text-red-700")
    elsif due_today
      tag.span("Due Today", class: "inline-flex items-center rounded-full bg-amber-100 px-2 py-0.5 text-xs font-semibold text-amber-700")
    elsif alert.scheduled?
      tag.span("Scheduled", class: "inline-flex items-center rounded-full bg-gray-100 px-2 py-0.5 text-xs font-semibold text-gray-600")
    else
      tag.span("Upcoming", class: "inline-flex items-center rounded-full bg-blue-100 px-2 py-0.5 text-xs font-semibold text-blue-700")
    end
  end

  def audit_log_action_badge(action)
    colors = {
      "created"    => "bg-green-50 text-green-700 ring-green-600/20",
      "updated"    => "bg-blue-50 text-blue-700 ring-blue-600/20",
      "deleted"    => "bg-red-50 text-red-700 ring-red-600/20",
      "viewed"     => "bg-gray-50 text-gray-600 ring-gray-500/20",
      "exported"   => "bg-purple-50 text-purple-700 ring-purple-600/20",
      "alert_sent" => "bg-amber-50 text-amber-700 ring-amber-600/20",
      "review_progress_saved" => "bg-amber-50 text-amber-700 ring-amber-600/20",
      "review_bulk_confirmed" => "bg-orange-50 text-orange-700 ring-orange-600/20",
      "review_field_confirmed" => "bg-green-50 text-green-700 ring-green-600/20",
      "review_field_edited" => "bg-blue-50 text-blue-700 ring-blue-600/20",
      "review_field_marked_not_found" => "bg-red-50 text-red-700 ring-red-600/20",
      "review_field_marked_not_applicable" => "bg-purple-50 text-purple-700 ring-purple-600/20",
      "review_completed" => "bg-emerald-50 text-emerald-700 ring-emerald-600/20",
      "review_alerts_activated" => "bg-teal-50 text-teal-700 ring-teal-600/20",
      "review_alerts_skipped" => "bg-gray-50 text-gray-600 ring-gray-500/20",
      "member_invited" => "bg-indigo-50 text-indigo-700 ring-indigo-600/20",
      "member_removed" => "bg-rose-50 text-rose-700 ring-rose-600/20",
      "member_role_changed" => "bg-indigo-50 text-indigo-700 ring-indigo-600/20",
      "invitation_revoked" => "bg-rose-50 text-rose-700 ring-rose-600/20"
    }
    color_class = colors[action] || "bg-gray-50 text-gray-600 ring-gray-500/20"
    label = AuditLog.new(action:).action_label
    tag.span(label, class: "inline-flex items-center rounded-full px-2 py-1 text-xs font-medium ring-1 ring-inset #{color_class}")
  end

  def audit_log_icon_bg(action)
    {
      "created"    => "bg-green-100",
      "updated"    => "bg-blue-100",
      "deleted"    => "bg-red-100",
      "viewed"     => "bg-gray-100",
      "exported"   => "bg-purple-100",
      "alert_sent" => "bg-amber-100",
      "review_progress_saved" => "bg-amber-100",
      "review_bulk_confirmed" => "bg-orange-100",
      "review_field_confirmed" => "bg-green-100",
      "review_field_edited" => "bg-blue-100",
      "review_field_marked_not_found" => "bg-red-100",
      "review_field_marked_not_applicable" => "bg-purple-100",
      "review_completed" => "bg-emerald-100",
      "review_alerts_activated" => "bg-teal-100",
      "review_alerts_skipped" => "bg-gray-100"
    }[action] || "bg-gray-100"
  end

  def audit_log_icon(action)
    icon_class = {
      "created"    => "text-green-600",
      "updated"    => "text-blue-600",
      "deleted"    => "text-red-600",
      "viewed"     => "text-gray-500",
      "exported"   => "text-purple-600",
      "alert_sent" => "text-amber-600",
      "review_progress_saved" => "text-amber-600",
      "review_bulk_confirmed" => "text-orange-600",
      "review_field_confirmed" => "text-green-600",
      "review_field_edited" => "text-blue-600",
      "review_field_marked_not_found" => "text-red-600",
      "review_field_marked_not_applicable" => "text-purple-600",
      "review_completed" => "text-emerald-600",
      "review_alerts_activated" => "text-teal-600",
      "review_alerts_skipped" => "text-gray-500"
    }[action] || "text-gray-500"

    paths = {
      "created"    => "M12 4.5v15m7.5-7.5h-15",
      "updated"    => "M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931z",
      "deleted"    => "M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0",
      "viewed"     => "M2.036 12.322a1.012 1.012 0 010-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178z M15 12a3 3 0 11-6 0 3 3 0 016 0z",
      "exported"   => "M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5M16.5 12L12 16.5m0 0L7.5 12m4.5 4.5V3",
      "alert_sent" => "M14.857 17.082a23.848 23.848 0 005.454-1.31A8.967 8.967 0 0118 9.75v-.7V9A6 6 0 006 9v.75a8.967 8.967 0 01-2.312 6.022c1.733.64 3.56 1.085 5.455 1.31m5.714 0a24.255 24.255 0 01-5.714 0m5.714 0a3 3 0 11-5.714 0",
      "review_progress_saved" => "M12 6v6l4 2.25",
      "review_bulk_confirmed" => "M9 12.75L11.25 15 15 9.75m6 2.25a9 9 0 11-18 0 9 9 0 0118 0z",
      "review_field_confirmed" => "M9 12.75L11.25 15 15 9.75",
      "review_field_edited" => "M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931z",
      "review_field_marked_not_found" => "M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z",
      "review_field_marked_not_applicable" => "M18.364 5.636l-12.728 12.728M5.636 5.636l12.728 12.728",
      "review_completed" => "M4.5 12.75l6 6 9-13.5",
      "review_alerts_activated" => "M14.857 17.082a23.848 23.848 0 005.454-1.31A8.967 8.967 0 0118 9.75v-.7V9A6 6 0 006 9v.75a8.967 8.967 0 01-2.312 6.022c1.733.64 3.56 1.085 5.455 1.31m5.714 0a24.255 24.255 0 01-5.714 0m5.714 0a3 3 0 11-5.714 0",
      "review_alerts_skipped" => "M12 6v6m0 4.5h.008v.008H12v-.008z"
    }
    path_d = paths[action] || paths["viewed"]

    tag.svg(class: "h-3.5 w-3.5 #{icon_class}", fill: "none", viewBox: "0 0 24 24", stroke_width: "1.5", stroke: "currentColor") do
      tag.path(stroke_linecap: "round", stroke_linejoin: "round", d: path_d)
    end
  end

  def review_readiness_badge(field)
    label = case field.readiness_bucket
    when "blocked" then "Blocked"
    when "needs_review" then "Needs Review"
    when "looks_good" then field.review_status == "pending" ? "Looks Good" : "Resolved"
    else "Pending"
    end

    color = case field.readiness_bucket
    when "blocked" then "bg-red-50 text-red-700 ring-red-600/20"
    when "needs_review" then "bg-amber-50 text-amber-700 ring-amber-600/20"
    when "looks_good" then "bg-green-50 text-green-700 ring-green-600/20"
    else "bg-gray-50 text-gray-600 ring-gray-500/20"
    end

    tag.span(label, class: "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset #{color}")
  end

  def review_status_badge(review_status)
    color = {
      "pending" => "bg-gray-50 text-gray-600 ring-gray-500/20",
      "confirmed" => "bg-green-50 text-green-700 ring-green-600/20",
      "edited" => "bg-blue-50 text-blue-700 ring-blue-600/20",
      "not_found" => "bg-red-50 text-red-700 ring-red-600/20",
      "not_applicable" => "bg-purple-50 text-purple-700 ring-purple-600/20"
    }.fetch(review_status, "bg-gray-50 text-gray-600 ring-gray-500/20")

    tag.span(review_status.titleize.gsub("_", " "), class: "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset #{color}")
  end

  def review_field_label(field)
    field.field_key.split(".").last.titleize.gsub("_", " ")
  end

  def review_field_group_context(field, contract)
    return nil unless field.field_index.present?

    data = JSON.parse(contract.ai_extracted_data || "{}") rescue {}

    case field.field_key
    when /^rent_escalation\./
      esc = data["rent_escalations"]&.[](field.field_index)
      return nil unless esc
      parts = []
      parts << Date.parse(esc["effective_date"]).strftime("%b %Y") if esc["effective_date"]
      parts << number_to_currency(esc["base_rent_monthly"], precision: 0) + "/mo" if esc["base_rent_monthly"]
      parts.join(" · ").presence
    when /^lease_option\./
      opt = data["lease_options"]&.[](field.field_index)
      return nil unless opt
      opt["option_type"]&.titleize
    when /^lease_milestone\./, /^recurring_milestone/
      ms = data["lease_milestones"]&.[](field.field_index)
      return nil unless ms
      parts = []
      parts << ms["milestone_type"]&.titleize&.tr("_", " ")
      parts << Date.parse(ms["due_date"]).strftime("%b %d, %Y") if ms["due_date"]
      parts.join(" · ").presence
    end
  rescue Date::Error
    nil
  end

  def review_field_description(field)
    ReviewFieldCatalog.fetch(field.field_key).notes
  rescue KeyError
    nil
  end

  def display_review_value(value)
    case value
    when true then "Yes"
    when false then "No"
    when String
      parsed_date = begin
        Date.iso8601(value)
      rescue ArgumentError
        nil
      end
      parsed_date ? format_date(parsed_date) : value.presence || "—"
    when Numeric
      value % 1 == 0 ? number_with_delimiter(value.to_i) : number_with_precision(value, precision: 2, strip_insignificant_zeros: true)
    else
      value.presence || "—"
    end
  end

  def review_field_input_kind(field)
    definition = ReviewFieldCatalog.fetch(field.field_key)
    return :date if ContractReviewValueResolver::DATE_FIELD_KEYS.include?(field.field_key)
    return :boolean if definition.field_family == "alert_governing_boolean"
    return :number if field.field_key.in?(ContractReviewValueResolver::INTEGER_FIELD_KEYS + ContractReviewValueResolver::DECIMAL_FIELD_KEYS)

    :text
  rescue KeyError
    :text
  end

  def review_field_form_value(field)
    value = field.effective_value
    return nil if value.nil?

    review_field_input_kind(field) == :boolean ? value.to_s : value
  end

  private

  def sidebar_icon(name, active: false)
    color = active ? "text-white" : "text-gray-400 group-hover:text-white"

    case name
    when :home
      tag.svg(class: "h-5 w-5 shrink-0 #{color}", fill: "none", viewBox: "0 0 24 24", stroke_width: "1.5", stroke: "currentColor") do
        tag.path(stroke_linecap: "round", stroke_linejoin: "round", d: "M2.25 12l8.954-8.955a1.126 1.126 0 011.591 0L21.75 12M4.5 9.75v10.125c0 .621.504 1.125 1.125 1.125H9.75v-4.875c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125V21h4.125c.621 0 1.125-.504 1.125-1.125V9.75M8.25 21h8.25")
      end
    when :document
      tag.svg(class: "h-5 w-5 shrink-0 #{color}", fill: "none", viewBox: "0 0 24 24", stroke_width: "1.5", stroke: "currentColor") do
        tag.path(stroke_linecap: "round", stroke_linejoin: "round", d: "M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z")
      end
    when :bell
      tag.svg(class: "h-5 w-5 shrink-0 #{color}", fill: "none", viewBox: "0 0 24 24", stroke_width: "1.5", stroke: "currentColor") do
        tag.path(stroke_linecap: "round", stroke_linejoin: "round", d: "M14.857 17.082a23.848 23.848 0 005.454-1.31A8.967 8.967 0 0118 9.75v-.7V9A6 6 0 006 9v.75a8.967 8.967 0 01-2.312 6.022c1.733.64 3.56 1.085 5.455 1.31m5.714 0a24.255 24.255 0 01-5.714 0m5.714 0a3 3 0 11-5.714 0")
      end
    when :clock
      tag.svg(class: "h-5 w-5 shrink-0 #{color}", fill: "none", viewBox: "0 0 24 24", stroke_width: "1.5", stroke: "currentColor") do
        tag.path(stroke_linecap: "round", stroke_linejoin: "round", d: "M12 6v6h4.5m4.5 0a9 9 0 11-18 0 9 9 0 0118 0z")
      end
    when :credit_card
      tag.svg(class: "h-5 w-5 shrink-0 #{color}", fill: "none", viewBox: "0 0 24 24", stroke_width: "1.5", stroke: "currentColor") do
        tag.path(stroke_linecap: "round", stroke_linejoin: "round", d: "M2.25 8.25h19.5M2.25 9h19.5m-16.5 5.25h6m-6 2.25h3m-3.75 3h15a2.25 2.25 0 002.25-2.25V6.75A2.25 2.25 0 0019.5 4.5h-15a2.25 2.25 0 00-2.25 2.25v10.5A2.25 2.25 0 004.5 19.5z")
      end
    when :users
      tag.svg(class: "h-5 w-5 shrink-0 #{color}", fill: "none", viewBox: "0 0 24 24", stroke_width: "1.5", stroke: "currentColor") do
        tag.path(stroke_linecap: "round", stroke_linejoin: "round", d: "M15 19.128a9.38 9.38 0 002.625.372 9.337 9.337 0 004.121-.952 4.125 4.125 0 00-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 018.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0111.964-3.07M12 6.375a3.375 3.375 0 11-6.75 0 3.375 3.375 0 016.75 0zm8.25 2.25a2.625 2.625 0 11-5.25 0 2.625 2.625 0 015.25 0z")
      end
    when :building
      tag.svg(class: "h-5 w-5 shrink-0 #{color}", fill: "none", viewBox: "0 0 24 24", stroke_width: "1.5", stroke: "currentColor") do
        tag.path(stroke_linecap: "round", stroke_linejoin: "round", d: "M3.75 21h16.5M4.5 3h15M5.25 3v18m13.5-18v18M9 6.75h1.5m-1.5 3h1.5m-1.5 3h1.5m3-6H15m-1.5 3H15m-1.5 3H15M9 21v-3.375c0-.621.504-1.125 1.125-1.125h3.75c.621 0 1.125.504 1.125 1.125V21")
      end
    else
      "".html_safe
    end
  end
end
