class AlertMailer < ApplicationMailer
  def alert_notification(alert_recipient)
    @recipient = alert_recipient
    @alert = alert_recipient.alert
    @contract = @alert.contract
    @user = alert_recipient.user

    mail(
      to: @user.email_address,
      subject: subject_for(@alert)
    )
  end

  private

  def subject_for(alert)
    case alert.alert_type
    when "renewal_upcoming"
      "Contract renewal upcoming: #{alert.contract.title}"
    when "expiry_warning"
      "Contract expiring soon: #{alert.contract.title}"
    when "notice_period_start"
      "Notice period starting: #{alert.contract.title}"
    else
      "Contract alert: #{alert.contract.title}"
    end
  end
end
