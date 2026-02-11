class AlertDeliveryService
  # Delivers a single alert to all its recipients.
  # Checks each recipient's AlertPreference for channel enablement.
  # Sends email via AlertMailer, marks in_app as delivered.
  # Updates alert status to "sent" when all recipients are processed.

  def initialize(alert)
    @alert = alert
  end

  def call
    return unless @alert.status == "pending"

    # Guard: don't deliver alerts for expired/cancelled contracts
    if @alert.contract&.status&.in?(%w[expired cancelled])
      @alert.update!(status: "cancelled")
      return
    end

    @alert.alert_recipients.unsent.includes(:user).find_each do |recipient|
      deliver_to(recipient)
    end

    @alert.update!(status: "sent")

    # Log audit entry for alert delivery
    if @alert.organization
      AuditLog.create(
        organization: @alert.organization,
        contract: @alert.contract,
        action: "alert_sent",
        details: "Delivered #{@alert.alert_type_label} alert for #{@alert.contract&.title}"
      )
    end
  end

  private

  def deliver_to(recipient)
    pref = preference_for(recipient.user)

    case recipient.channel
    when "email"
      AlertMailer.alert_notification(recipient).deliver_later if pref.email_enabled
    when "in_app"
      # In-app alerts are "delivered" immediately — they just show up in the UI
    end

    recipient.mark_as_sent!
  rescue => e
    Rails.logger.error("Failed to deliver alert #{@alert.id} to #{recipient.user.email_address}: #{e.message}")
  end

  def preference_for(user)
    user.alert_preferences.find_by(organization: @alert.organization) ||
      AlertPreference.new(email_enabled: true, in_app_enabled: true)
  end
end
