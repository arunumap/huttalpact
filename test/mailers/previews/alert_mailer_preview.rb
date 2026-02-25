# Preview all emails at http://localhost:3000/rails/mailers/alert_mailer
class AlertMailerPreview < ActionMailer::Preview
  # Preview at http://localhost:3000/rails/mailers/alert_mailer/expiry_warning
  def expiry_warning
    recipient = AlertRecipient.joins(:alert).where(alerts: { alert_type: "expiry_warning" }).first
    recipient ||= build_sample_recipient(alert_type: "expiry_warning")
    AlertMailer.alert_notification(recipient)
  end

  # Preview at http://localhost:3000/rails/mailers/alert_mailer/renewal_upcoming
  def renewal_upcoming
    recipient = AlertRecipient.joins(:alert).where(alerts: { alert_type: "renewal_upcoming" }).first
    recipient ||= build_sample_recipient(alert_type: "renewal_upcoming")
    AlertMailer.alert_notification(recipient)
  end

  # Preview at http://localhost:3000/rails/mailers/alert_mailer/notice_period_start
  def notice_period_start
    recipient = AlertRecipient.joins(:alert).where(alerts: { alert_type: "notice_period_start" }).first
    recipient ||= build_sample_recipient(alert_type: "notice_period_start")
    AlertMailer.alert_notification(recipient)
  end

  private

  def build_sample_recipient(alert_type:)
    user = User.first || User.new(email_address: "preview@example.com", first_name: "Jane", last_name: "Doe")
    organization = Organization.first || Organization.new(name: "Sample Org")
    contract = Contract.first || Contract.new(
      id: "00000000-0000-0000-0000-000000000000",
      title: "Sample Contract",
      organization: organization,
      vendor_name: "Acme Corp",
      status: "active",
      start_date: 1.year.ago.to_date,
      end_date: 30.days.from_now.to_date,
      next_renewal_date: 30.days.from_now.to_date,
      notice_period_days: 30,
      auto_renews: true,
      renewal_term: "12 months",
      monthly_value: 2500
    )
    alert = Alert.new(
      alert_type: alert_type,
      status: "pending",
      trigger_date: Date.current,
      contract: contract,
      organization: organization
    )
    AlertRecipient.new(alert: alert, user: user, channel: "email")
  end
end
