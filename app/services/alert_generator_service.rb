class AlertGeneratorService
  # Generates alerts from a contract's dates (end_date, next_renewal_date, notice_period_days).
  # Idempotent: clears existing pending/snoozed alerts for the contract, then recreates.
  # Never touches sent or acknowledged alerts.

  def initialize(contract)
    @contract = contract
    @organization = contract.organization
  end

  def call
    return if skip_contract?

    clear_regenerable_alerts!
    generate_expiry_alerts
    generate_renewal_alerts
    generate_notice_period_alerts

    # Lease-specific alerts
    if @contract.lease?
      generate_option_exercise_alerts
      generate_rent_escalation_alerts
      generate_cam_reconciliation_alerts
      generate_ti_deadline_alerts
      generate_lease_milestone_alerts
    end
  end

  private

  def skip_contract?
    @contract.status.in?(%w[expired cancelled])
  end

  def clear_regenerable_alerts!
    @contract.alerts.where(status: %w[pending snoozed]).destroy_all
  end

  def generate_expiry_alerts
    return unless @contract.end_date.present?
    return if @contract.end_date <= Date.current

    each_member_preference do |user, pref|
      trigger_date = @contract.end_date - pref.days_before_expiry.days

      next if trigger_date <= Date.current && already_alerted?(user, "expiry_warning")

      create_alert(
        alert_type: "expiry_warning",
        trigger_date: [ trigger_date, Date.current ].max,
        message: "#{@contract.title} — expiry on #{@contract.end_date.strftime('%b %-d, %Y')}",
        user: user,
        pref: pref
      )
    end
  end

  def generate_renewal_alerts
    return unless @contract.next_renewal_date.present?
    return if @contract.next_renewal_date <= Date.current

    each_member_preference do |user, pref|
      trigger_date = @contract.next_renewal_date - pref.days_before_renewal.days

      next if trigger_date <= Date.current && already_alerted?(user, "renewal_upcoming")

      create_alert(
        alert_type: "renewal_upcoming",
        trigger_date: [ trigger_date, Date.current ].max,
        message: "#{@contract.title} — renewal on #{@contract.next_renewal_date.strftime('%b %-d, %Y')}",
        user: user,
        pref: pref
      )
    end
  end

  def generate_notice_period_alerts
    return unless @contract.notice_period_days.present? && @contract.notice_period_days > 0

    reference_date = @contract.next_renewal_date || @contract.end_date
    return unless reference_date.present?

    notice_start = reference_date - @contract.notice_period_days.days
    return if notice_start <= Date.current

    each_member_preference do |user, pref|
      next if already_alerted?(user, "notice_period_start")

      create_alert(
        alert_type: "notice_period_start",
        trigger_date: notice_start,
        message: "#{@contract.title} — notice period #{@contract.notice_period_days} days before #{reference_date.strftime('%b %-d, %Y')}",
        user: user,
        pref: pref
      )
    end
  end

  # --- Lease-specific alert generators ---

  def generate_option_exercise_alerts
    @contract.lease_options.each do |option|
      next unless option.notice_deadline.present?
      next if option.notice_deadline <= Date.current

      each_member_preference do |user, pref|
        lead_days = pref.days_before_option_exercise || 90
        trigger_date = option.notice_deadline - lead_days.days

        next if trigger_date <= Date.current && already_alerted?(user, "option_exercise_deadline")

        create_alert(
          alert_type: "option_exercise_deadline",
          trigger_date: [ trigger_date, Date.current ].max,
          message: "#{option.option_type_label} option notice deadline for #{@contract.title} — #{option.notice_deadline.strftime('%b %-d, %Y')}",
          user: user,
          pref: pref
        )
      end
    end
  end

  def generate_rent_escalation_alerts
    @contract.rent_escalations.future.each do |escalation|
      each_member_preference do |user, pref|
        lead_days = pref.days_before_rent_escalation || 30
        trigger_date = escalation.effective_date - lead_days.days

        next if trigger_date <= Date.current && already_alerted?(user, "rent_escalation_date")

        create_alert(
          alert_type: "rent_escalation_date",
          trigger_date: [ trigger_date, Date.current ].max,
          message: "Rent escalation for #{@contract.title} — effective #{escalation.effective_date.strftime('%b %-d, %Y')} (#{escalation.escalation_type_label})",
          user: user,
          pref: pref
        )
      end
    end
  end

  def generate_cam_reconciliation_alerts
    lease_detail = @contract.lease_detail
    return unless lease_detail&.cam_reconciliation_month.present?

    next_recon_date = lease_detail.next_cam_reconciliation_date
    return unless next_recon_date.present?

    each_member_preference do |user, pref|
      lead_days = pref.days_before_cam_reconciliation || 30
      trigger_date = next_recon_date - lead_days.days

      next if trigger_date <= Date.current && already_alerted?(user, "cam_reconciliation")

      create_alert(
        alert_type: "cam_reconciliation",
        trigger_date: [ trigger_date, Date.current ].max,
        message: "CAM reconciliation for #{@contract.title} — #{next_recon_date.strftime('%b %Y')}",
        user: user,
        pref: pref
      )
    end
  end

  def generate_ti_deadline_alerts
    lease_detail = @contract.lease_detail
    return unless lease_detail&.ti_deadline.present?
    return if lease_detail.ti_deadline <= Date.current

    each_member_preference do |user, pref|
      lead_days = pref.days_before_milestone || 14
      trigger_date = lease_detail.ti_deadline - lead_days.days

      next if trigger_date <= Date.current && already_alerted?(user, "ti_deadline")

      create_alert(
        alert_type: "ti_deadline",
        trigger_date: [ trigger_date, Date.current ].max,
        message: "TI allowance deadline for #{@contract.title} — use by #{lease_detail.ti_deadline.strftime('%b %-d, %Y')}",
        user: user,
        pref: pref
      )
    end
  end

  def generate_lease_milestone_alerts
    @contract.lease_milestones.each do |milestone|
      target_date = milestone.recurring? ? milestone.next_occurrence_date : milestone.due_date
      next if target_date.nil? || target_date <= Date.current

      each_member_preference do |user, pref|
        lead_days = pref.days_before_milestone || 14
        trigger_date = target_date - lead_days.days

        next if trigger_date <= Date.current && already_alerted?(user, "milestone_reminder")

        create_alert(
          alert_type: "milestone_reminder",
          trigger_date: [ trigger_date, Date.current ].max,
          message: "#{milestone.milestone_type_label} — #{milestone.description || @contract.title}",
          user: user,
          pref: pref
        )
      end
    end
  end

  def each_member_preference(&block)
    @organization.users.includes(:alert_preferences).find_each do |user|
      pref = user.alert_preferences.find_by(organization: @organization) ||
             AlertPreference.new(
               days_before_renewal: 30, days_before_expiry: 14,
               days_before_option_exercise: 90, days_before_rent_escalation: 30,
               days_before_cam_reconciliation: 30, days_before_milestone: 14,
               email_enabled: true, in_app_enabled: true
             )
      yield user, pref
    end
  end

  def create_alert(alert_type:, trigger_date:, message:, user:, pref:)
    # Skip entirely if user has opted out of both channels
    return if !pref.email_enabled && !pref.in_app_enabled

    alert = @contract.alerts.find_or_create_by!(
      organization: @organization,
      alert_type: alert_type,
      trigger_date: trigger_date
    ) do |a|
      a.message = message
      a.status = "pending"
    end

    # Every alert is inherently in-app. Email is an additional notification
    # channel handled at delivery time based on pref.email_enabled.
    alert.alert_recipients.find_or_create_by!(user: user) do |r|
      r.channel = "in_app"
    end
  end

  def already_alerted?(user, alert_type)
    @contract.alerts
      .where(alert_type: alert_type, status: %w[sent acknowledged])
      .joins(:alert_recipients)
      .where(alert_recipients: { user_id: user.id })
      .exists?
  end
end
