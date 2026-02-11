require "test_helper"

class AlertMailerTest < ActionMailer::TestCase
  setup do
    @recipient = alert_recipients(:one_expiry)
  end

  test "alert_notification sends to correct recipient" do
    email = AlertMailer.alert_notification(@recipient)
    assert_equal [ users(:one).email_address ], email.to
  end

  test "alert_notification from address is set" do
    email = AlertMailer.alert_notification(@recipient)
    assert_equal [ "notifications@huttalpact.com" ], email.from
  end

  test "expiry_warning has correct subject" do
    email = AlertMailer.alert_notification(@recipient)
    assert_equal "Contract expiring soon: Landscaping Services", email.subject
  end

  test "renewal_upcoming has correct subject" do
    recipient = alert_recipients(:one_renewal)
    email = AlertMailer.alert_notification(recipient)
    assert_equal "Contract renewal upcoming: HVAC Maintenance - Building A", email.subject
  end

  test "notice_period_start has correct subject" do
    recipient = alert_recipients(:one_acknowledged)
    email = AlertMailer.alert_notification(recipient)
    assert_equal "Notice period starting: HVAC Maintenance - Building A", email.subject
  end

  test "html body contains contract title" do
    email = AlertMailer.alert_notification(@recipient)
    assert_match "Landscaping Services", email.html_part.body.to_s
  end

  test "html body contains vendor name" do
    email = AlertMailer.alert_notification(@recipient)
    assert_match "Green Thumb LLC", email.html_part.body.to_s
  end

  test "html body contains contract URL" do
    email = AlertMailer.alert_notification(@recipient)
    assert_match @recipient.alert.contract.id, email.html_part.body.to_s
  end

  test "text body contains contract title" do
    email = AlertMailer.alert_notification(@recipient)
    assert_match "Landscaping Services", email.text_part.body.to_s
  end

  test "text body contains vendor name" do
    email = AlertMailer.alert_notification(@recipient)
    assert_match "Green Thumb LLC", email.text_part.body.to_s
  end

  test "renewal alert mentions auto-renew when applicable" do
    recipient = alert_recipients(:one_renewal)
    email = AlertMailer.alert_notification(recipient)
    # hvac_maintenance has auto_renews: true
    assert_match "auto-renew", email.html_part.body.to_s
  end

  test "expiry alert mentions expiry date" do
    email = AlertMailer.alert_notification(@recipient)
    contract = @recipient.alert.contract
    assert_match contract.end_date.strftime("%B %d, %Y"), email.html_part.body.to_s
  end

  test "email contains user first name" do
    email = AlertMailer.alert_notification(@recipient)
    assert_match "Alice", email.html_part.body.to_s
  end

  test "monthly value is included when present" do
    email = AlertMailer.alert_notification(@recipient)
    assert_match "$800.00", email.html_part.body.to_s
  end
end
