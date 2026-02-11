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

  def each_member_preference(&block)
    @organization.users.includes(:alert_preferences).find_each do |user|
      pref = user.alert_preferences.find_by(organization: @organization) ||
             AlertPreference.new(days_before_renewal: 30, days_before_expiry: 14, email_enabled: true, in_app_enabled: true)
      yield user, pref
    end
  end

  def create_alert(alert_type:, trigger_date:, message:, user:, pref:)
    alert = @contract.alerts.find_or_create_by!(
      organization: @organization,
      alert_type: alert_type,
      trigger_date: trigger_date
    ) do |a|
      a.message = message
      a.status = "pending"
    end

    alert.alert_recipients.find_or_create_by!(user: user) do |r|
      r.channel = pref.email_enabled ? "email" : "in_app"
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
