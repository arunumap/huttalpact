# Preview all emails at http://localhost:3000/rails/mailers/alert_mailer
class AlertMailerPreview < ActionMailer::Preview
  # Preview at http://localhost:3000/rails/mailers/alert_mailer/expiry_warning
  def expiry_warning
    recipient = AlertRecipient.joins(:alert).where(alerts: { alert_type: "expiry_warning" }).first
    recipient ||= AlertRecipient.first
    AlertMailer.alert_notification(recipient)
  end

  # Preview at http://localhost:3000/rails/mailers/alert_mailer/renewal_upcoming
  def renewal_upcoming
    recipient = AlertRecipient.joins(:alert).where(alerts: { alert_type: "renewal_upcoming" }).first
    recipient ||= AlertRecipient.first
    AlertMailer.alert_notification(recipient)
  end

  # Preview at http://localhost:3000/rails/mailers/alert_mailer/notice_period_start
  def notice_period_start
    recipient = AlertRecipient.joins(:alert).where(alerts: { alert_type: "notice_period_start" }).first
    recipient ||= AlertRecipient.first
    AlertMailer.alert_notification(recipient)
  end
end
