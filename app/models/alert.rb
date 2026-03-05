class Alert < ApplicationRecord
  acts_as_tenant :organization

  belongs_to :organization
  belongs_to :contract
  has_many :alert_recipients, dependent: :destroy

  ALERT_TYPES = %w[
    renewal_upcoming
    expiry_warning
    notice_period_start
    option_exercise_deadline
    rent_escalation_date
    cam_reconciliation
    ti_deadline
    milestone_reminder
  ].freeze
  STATUSES = %w[pending sent acknowledged snoozed cancelled].freeze

  validates :alert_type, presence: true, inclusion: { in: ALERT_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :trigger_date, presence: true

  UPCOMING_HORIZON_DAYS = 90
  LEAD_DAY_DEFAULTS = {
    renewal_upcoming: 30,
    expiry_warning: 14,
    notice_period_start: 30,
    option_exercise_deadline: 90,
    rent_escalation_date: 30,
    cam_reconciliation: 30,
    ti_deadline: 14,
    milestone_reminder: 14
  }.freeze

  scope :pending, -> { where(status: "pending") }
  scope :sent, -> { where(status: "sent") }
  scope :unacknowledged, -> { where(status: %w[pending sent]) }
  scope :due_today, -> { where(trigger_date: Date.current) }
  scope :due_on_or_before, ->(date) { where(trigger_date: ..date) }
  scope :overdue, -> { due_on_or_before(Date.current).where(status: "pending") }
  scope :upcoming, -> { where(trigger_date: (Date.current + 1)..(Date.current + UPCOMING_HORIZON_DAYS)) }
  scope :scheduled, -> { where(trigger_date: (Date.current + UPCOMING_HORIZON_DAYS + 1)..) }
  scope :actionable, -> { where(trigger_date: ..(Date.current + UPCOMING_HORIZON_DAYS)) }
  scope :for_user, ->(user) { joins(:alert_recipients).where(alert_recipients: { user_id: user.id }) }

  # Returns alerts visible to a specific user: unread AND not currently snoozed
  scope :visible_to, ->(user) {
    joins(:alert_recipients)
      .where(alert_recipients: { user_id: user.id, read_at: nil })
      .where("alert_recipients.snoozed_until IS NULL OR alert_recipients.snoozed_until <= ?", Date.current)
      .where(status: %w[pending sent])
  }

  def alert_type_label
    alert_type.titleize.gsub("_", " ")
  end

  def overdue?
    trigger_date < Date.current && status.in?(%w[pending sent])
  end

  def due_today?
    trigger_date == Date.current
  end

  def scheduled?
    trigger_date > Date.current + UPCOMING_HORIZON_DAYS && status.in?(%w[pending sent])
  end

  def window_end_for(alert_preference = nil)
    trigger_date + lead_days_for(alert_preference)
  end

  def active_for_preference?(alert_preference, today: Date.current)
    return false unless status.in?(%w[pending sent])

    trigger_date <= today && today <= window_end_for(alert_preference)
  end

  def overdue_for_preference?(alert_preference, today: Date.current)
    return false unless status.in?(%w[pending sent])

    today > window_end_for(alert_preference)
  end

  def due_today_for_preference?(alert_preference, today: Date.current)
    return false unless status.in?(%w[pending sent])

    today == window_end_for(alert_preference)
  end

  def lead_days_for(alert_preference = nil)
    case alert_type
    when "renewal_upcoming"
      preference_days(alert_preference&.days_before_renewal, :renewal_upcoming)
    when "expiry_warning"
      preference_days(alert_preference&.days_before_expiry, :expiry_warning)
    when "notice_period_start"
      preference_days(contract.notice_period_days, :notice_period_start)
    when "option_exercise_deadline"
      preference_days(alert_preference&.days_before_option_exercise, :option_exercise_deadline)
    when "rent_escalation_date"
      preference_days(alert_preference&.days_before_rent_escalation, :rent_escalation_date)
    when "cam_reconciliation"
      preference_days(alert_preference&.days_before_cam_reconciliation, :cam_reconciliation)
    when "ti_deadline"
      preference_days(alert_preference&.days_before_milestone, :ti_deadline)
    when "milestone_reminder"
      preference_days(alert_preference&.days_before_milestone, :milestone_reminder)
    else
      0
    end
  end

  def display_message(alert_preference: nil)
    using_window_semantics = alert_preference.present?
    days_until = if using_window_semantics
      (window_end_for(alert_preference) - Date.current).to_i
    else
      (trigger_date - Date.current).to_i
    end
    overdue = using_window_semantics ? overdue_for_preference?(alert_preference) : overdue?
    due_today = using_window_semantics ? due_today_for_preference?(alert_preference) : due_today?
    event_date = contract_event_date(alert_preference: alert_preference)
    event_date_str = event_date&.strftime("%b %-d, %Y")

    case alert_type
    when "notice_period_start"
      notice_days = contract.notice_period_days
      if overdue
        "Notice period for #{contract.title} started #{pluralize_days(days_until.abs)} ago — #{notice_days} days before #{event_date_str}"
      elsif due_today
        "Notice period for #{contract.title} starts today — #{notice_days} days before #{event_date_str}"
      elsif scheduled?
        "Notice period for #{contract.title} starts on #{trigger_date.strftime('%b %-d, %Y')} — #{notice_days} days before #{event_date_str}"
      else
        "Notice period for #{contract.title} starts in #{pluralize_days(days_until)} — #{notice_days} days before #{event_date_str}"
      end
    when "expiry_warning"
      if overdue
        "#{contract.title} expired #{pluralize_days(days_until.abs)} ago on #{event_date_str}"
      elsif due_today
        "#{contract.title} expires today — #{event_date_str}"
      elsif scheduled?
        "#{contract.title} expires on #{event_date_str} (in #{humanize_duration(days_until)})"
      else
        "#{contract.title} expires in #{pluralize_days(days_until)} — #{event_date_str}"
      end
    when "renewal_upcoming"
      if overdue
        "#{contract.title} renewal was due #{pluralize_days(days_until.abs)} ago on #{event_date_str}"
      elsif due_today
        "#{contract.title} renewal is due today — #{event_date_str}"
      elsif scheduled?
        "#{contract.title} renews on #{event_date_str} (in #{humanize_duration(days_until)})"
      else
        "#{contract.title} renews in #{pluralize_days(days_until)} — #{event_date_str}"
      end
    when "option_exercise_deadline"
      if overdue
        "Option exercise deadline for #{contract.title} passed #{pluralize_days(days_until.abs)} ago"
      elsif due_today
        "Option exercise deadline for #{contract.title} is today!"
      else
        "Option exercise deadline for #{contract.title} in #{pluralize_days(days_until)} — #{event_date_str}"
      end
    when "rent_escalation_date"
      if overdue
        "Rent escalation for #{contract.title} took effect #{pluralize_days(days_until.abs)} ago"
      elsif due_today
        "Rent escalation for #{contract.title} takes effect today"
      else
        "Rent escalation for #{contract.title} in #{pluralize_days(days_until)} — #{event_date_str}"
      end
    when "cam_reconciliation"
      if overdue
        "CAM reconciliation for #{contract.title} was due #{pluralize_days(days_until.abs)} ago"
      elsif due_today
        "CAM reconciliation for #{contract.title} is due today"
      else
        "CAM reconciliation for #{contract.title} in #{pluralize_days(days_until)} — #{event_date_str}"
      end
    when "ti_deadline"
      if overdue
        "TI allowance deadline for #{contract.title} passed #{pluralize_days(days_until.abs)} ago"
      elsif due_today
        "TI allowance deadline for #{contract.title} is today — use it or lose it!"
      else
        "TI allowance deadline for #{contract.title} in #{pluralize_days(days_until)} — #{event_date_str}"
      end
    when "milestone_reminder"
      if overdue
        "#{message || 'Lease milestone'} for #{contract.title} was due #{pluralize_days(days_until.abs)} ago"
      elsif due_today
        "#{message || 'Lease milestone'} for #{contract.title} is due today"
      else
        "#{message || 'Lease milestone'} for #{contract.title} in #{pluralize_days(days_until)}"
      end
    else
      message
    end
  end

  def acknowledge!(user:)
    recipient = alert_recipients.find_by!(user: user)
    recipient.mark_as_read!

    # Transition alert to acknowledged only when ALL recipients have read it
    if alert_recipients.unread.none?
      update!(status: "acknowledged")
    end
  end

  def snooze!(user:, days:)
    recipient = alert_recipients.find_by!(user: user)
    recipient.update!(snoozed_until: Date.current + days.days)
  end

  private

  def contract_event_date(alert_preference: nil)
    case alert_type
    when "expiry_warning" then contract.end_date
    when "renewal_upcoming" then contract.next_renewal_date
    when "notice_period_start" then contract.next_renewal_date || contract.end_date
    when "option_exercise_deadline" then alert_preference.present? ? window_end_for(alert_preference) : trigger_date
    when "rent_escalation_date" then alert_preference.present? ? window_end_for(alert_preference) : trigger_date
    when "cam_reconciliation" then alert_preference.present? ? window_end_for(alert_preference) : trigger_date
    when "ti_deadline" then alert_preference.present? ? window_end_for(alert_preference) : contract.lease_detail&.ti_deadline
    when "milestone_reminder" then alert_preference.present? ? window_end_for(alert_preference) : trigger_date
    end
  end

  def preference_days(value, default_key)
    days = value.to_i
    return days if days.positive?

    LEAD_DAY_DEFAULTS.fetch(default_key)
  end

  def pluralize_days(count)
    count == 1 ? "1 day" : "#{count} days"
  end

  def humanize_duration(days)
    if days >= 365
      years = days / 365
      remaining_months = (days % 365) / 30
      parts = []
      parts << "#{years} #{"year".pluralize(years)}"
      parts << "#{remaining_months} #{"month".pluralize(remaining_months)}" if remaining_months > 0
      parts.join(", ")
    elsif days >= 30
      months = days / 30
      "#{months} #{"month".pluralize(months)}"
    else
      pluralize_days(days)
    end
  end
end
