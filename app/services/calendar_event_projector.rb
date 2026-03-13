# Converts contract domain records into provider-neutral calendar event candidates.
# Each candidate is a struct that can be mapped to any calendar provider's API.
class CalendarEventProjector
  CalendarCandidate = Struct.new(
    :source_type, :source_id, :event_category,
    :title, :date, :description, :deep_link_path,
    :recurrence_rule, :reminder_days,
    keyword_init: true
  ) do
    def fingerprint
      Digest::SHA256.hexdigest([ title, date.to_s, description, recurrence_rule ].join("|"))
    end
  end

  def initialize(organization:, user:)
    @organization = organization
    @user = user
    @alert_preference = AlertPreference.for(user, organization)
  end

  def project(categories: nil)
    allowed = categories || CalendarPreference::ALL_CATEGORIES
    candidates = []

    @organization.contracts.not_archived.includes(:lease_detail, :rent_escalations, :lease_options, :lease_milestones).find_each do |contract|
      next if contract.status.in?(%w[expired cancelled])

      candidates.concat(project_contract(contract, allowed))
    end

    candidates
  end

  private

  def project_contract(contract, allowed)
    candidates = []

    candidates << expiry_candidate(contract) if allowed.include?("expiry_warning")
    candidates << renewal_candidate(contract) if allowed.include?("renewal_upcoming")
    candidates << notice_period_candidate(contract) if allowed.include?("notice_period_start")

    if contract.lease?
      candidates.concat(option_exercise_candidates(contract)) if allowed.include?("option_exercise_deadline")
      candidates.concat(rent_escalation_candidates(contract)) if allowed.include?("rent_escalation_date")
      candidates << cam_reconciliation_candidate(contract) if allowed.include?("cam_reconciliation")
      candidates << ti_deadline_candidate(contract) if allowed.include?("ti_deadline")
      candidates.concat(milestone_candidates(contract)) if allowed.include?("milestone_reminder")
    end

    candidates.compact
  end

  def expiry_candidate(contract)
    return unless contract.end_date.present? && contract.end_date > Date.current

    CalendarCandidate.new(
      source_type: "Contract", source_id: contract.id,
      event_category: "expiry_warning",
      title: "#{contract.title} — Expires",
      date: contract.end_date,
      description: build_description(contract, "Contract expiration date"),
      deep_link_path: "/contracts/#{contract.id}",
      reminder_days: @alert_preference.days_before_expiry
    )
  end

  def renewal_candidate(contract)
    return unless contract.next_renewal_date.present? && contract.next_renewal_date > Date.current

    CalendarCandidate.new(
      source_type: "Contract", source_id: contract.id,
      event_category: "renewal_upcoming",
      title: "#{contract.title} — Renewal Due",
      date: contract.next_renewal_date,
      description: build_description(contract, "Contract renewal date"),
      deep_link_path: "/contracts/#{contract.id}",
      reminder_days: @alert_preference.days_before_renewal
    )
  end

  def notice_period_candidate(contract)
    return unless contract.notice_period_days.present? && contract.notice_period_days > 0

    reference_date = contract.next_renewal_date || contract.end_date
    return unless reference_date.present?

    notice_start = reference_date - contract.notice_period_days.days
    return unless notice_start > Date.current

    CalendarCandidate.new(
      source_type: "Contract", source_id: contract.id,
      event_category: "notice_period_start",
      title: "#{contract.title} — Notice Period Starts",
      date: notice_start,
      description: build_description(contract, "#{contract.notice_period_days}-day notice period begins"),
      deep_link_path: "/contracts/#{contract.id}",
      reminder_days: @alert_preference.days_before_renewal
    )
  end

  def option_exercise_candidates(contract)
    contract.lease_options.filter_map do |option|
      next unless option.notice_deadline.present? && option.notice_deadline > Date.current

      CalendarCandidate.new(
        source_type: "LeaseOption", source_id: option.id,
        event_category: "option_exercise_deadline",
        title: "#{contract.title} — #{option.option_type_label} Option Deadline",
        date: option.notice_deadline,
        description: build_description(contract, "Option exercise notice deadline"),
        deep_link_path: "/contracts/#{contract.id}",
        reminder_days: @alert_preference.days_before_option_exercise || 90
      )
    end
  end

  def rent_escalation_candidates(contract)
    contract.rent_escalations.future.filter_map do |escalation|
      CalendarCandidate.new(
        source_type: "RentEscalation", source_id: escalation.id,
        event_category: "rent_escalation_date",
        title: "#{contract.title} — Rent Escalation",
        date: escalation.effective_date,
        description: build_description(contract, "Rent escalation takes effect (#{escalation.escalation_type_label})"),
        deep_link_path: "/contracts/#{contract.id}",
        reminder_days: @alert_preference.days_before_rent_escalation || 30
      )
    end
  end

  def cam_reconciliation_candidate(contract)
    lease_detail = contract.lease_detail
    return unless lease_detail&.cam_reconciliation_month.present?

    next_date = lease_detail.next_cam_reconciliation_date
    return unless next_date.present?

    CalendarCandidate.new(
      source_type: "LeaseDetail", source_id: lease_detail.id,
      event_category: "cam_reconciliation",
      title: "#{contract.title} — CAM Reconciliation Due",
      date: next_date,
      description: build_description(contract, "Annual CAM/operating expense reconciliation"),
      deep_link_path: "/contracts/#{contract.id}",
      reminder_days: @alert_preference.days_before_cam_reconciliation || 30
    )
  end

  def ti_deadline_candidate(contract)
    lease_detail = contract.lease_detail
    return unless lease_detail&.ti_deadline.present? && lease_detail.ti_deadline > Date.current

    CalendarCandidate.new(
      source_type: "LeaseDetail", source_id: lease_detail.id,
      event_category: "ti_deadline",
      title: "#{contract.title} — TI Allowance Deadline",
      date: lease_detail.ti_deadline,
      description: build_description(contract, "Tenant improvement allowance expires — use it or lose it"),
      deep_link_path: "/contracts/#{contract.id}",
      reminder_days: @alert_preference.days_before_milestone || 14
    )
  end

  def milestone_candidates(contract)
    contract.lease_milestones.filter_map do |milestone|
      target_date = milestone.recurring? ? milestone.next_occurrence_date : milestone.due_date
      next if target_date.nil? || target_date <= Date.current

      recurrence = if milestone.recurring? && milestone.recurrence_interval.present?
        case milestone.recurrence_interval
        when "monthly" then "RRULE:FREQ=MONTHLY"
        when "quarterly" then "RRULE:FREQ=MONTHLY;INTERVAL=3"
        when "annual" then "RRULE:FREQ=YEARLY"
        end
      end

      CalendarCandidate.new(
        source_type: "LeaseMilestone", source_id: milestone.id,
        event_category: "milestone_reminder",
        title: "#{contract.title} — #{milestone.milestone_type_label}",
        date: target_date,
        description: build_description(contract, milestone.description || milestone.milestone_type_label),
        deep_link_path: "/contracts/#{contract.id}",
        recurrence_rule: recurrence,
        reminder_days: @alert_preference.days_before_milestone || 14
      )
    end
  end

  def build_description(contract, detail)
    parts = [ detail ]
    parts << "Contract: #{contract.title}"
    parts << "Type: #{contract.contract_type_label}" if contract.contract_type.present?
    parts << "Vendor: #{contract.vendor_name}" if contract.vendor_name.present?
    parts.join("\n")
  end
end
