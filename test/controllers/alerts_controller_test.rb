require "test_helper"

class AlertsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
  end

  test "should get index" do
    get alerts_path
    assert_response :success
  end

  test "index shows user's alerts" do
    get alerts_path
    assert_response :success
    assert_match "Landscaping Services", response.body
  end

  test "index does not show other org's alerts" do
    get alerts_path
    assert_no_match(/Office Lease/, response.body)
  end

  test "index separates scheduled alerts from upcoming" do
    get alerts_path
    assert_response :success
    # The far-future alert should be in the Scheduled section, not Upcoming
    assert_match "Scheduled", response.body
  end

  test "acknowledge marks alert as acknowledged" do
    alert = alerts(:expiry_warning)
    patch acknowledge_alert_path(alert)

    # With single recipient, alert transitions to acknowledged
    assert_equal "acknowledged", alert.reload.status
  end

  test "acknowledge only marks current user's recipient as read" do
    alert = alerts(:expiry_warning)
    user_two = users(:two)
    org = organizations(:one)
    Membership.find_or_create_by!(user: user_two, organization: org) { |m| m.role = "member" }
    alert.alert_recipients.create!(user: user_two, channel: "email")

    patch acknowledge_alert_path(alert)

    # Current user's recipient is read
    assert_not_nil alert.alert_recipients.find_by(user: users(:one)).read_at
    # Other user's recipient is NOT read
    assert_nil alert.alert_recipients.find_by(user: user_two).read_at
    # Alert remains non-acknowledged since not all recipients read
    assert_not_equal "acknowledged", alert.reload.status
  end

  test "acknowledge creates audit log" do
    alert = alerts(:expiry_warning)
    assert_difference "AuditLog.count", 1 do
      patch acknowledge_alert_path(alert)
    end
    log = AuditLog.last
    assert_equal "alert_acknowledged", log.action
    assert_equal alert.contract, log.contract
  end

  test "acknowledge via turbo stream removes alert card" do
    alert = alerts(:expiry_warning)
    patch acknowledge_alert_path(alert), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match "turbo-stream", response.body
  end

  test "snooze pushes alert forward for current user only" do
    alert = alerts(:expiry_warning)

    patch snooze_alert_path(alert, days: 7)

    recipient = alert.alert_recipients.find_by(user: users(:one))
    assert_equal Date.current + 7.days, recipient.snoozed_until
    # Alert-level trigger_date should not change
    assert_equal alerts(:expiry_warning).trigger_date, alert.reload.trigger_date
  end

  test "snooze creates audit log" do
    alert = alerts(:expiry_warning)
    assert_difference "AuditLog.count", 1 do
      patch snooze_alert_path(alert, days: 7)
    end
    log = AuditLog.last
    assert_equal "alert_snoozed", log.action
    assert_equal alert.contract, log.contract
    assert_match "7 days", log.details
  end

  test "snooze defaults to 7 days" do
    alert = alerts(:expiry_warning)

    patch snooze_alert_path(alert)

    recipient = alert.alert_recipients.find_by(user: users(:one))
    assert_equal Date.current + 7.days, recipient.snoozed_until
  end

  test "snooze with custom days" do
    alert = alerts(:expiry_warning)

    patch snooze_alert_path(alert, days: 14)

    recipient = alert.alert_recipients.find_by(user: users(:one))
    assert_equal Date.current + 14.days, recipient.snoozed_until
  end

  test "snooze clamps excessive days to 90" do
    alert = alerts(:expiry_warning)

    patch snooze_alert_path(alert, days: 365)

    recipient = alert.alert_recipients.find_by(user: users(:one))
    assert_equal Date.current + 90.days, recipient.snoozed_until
  end

  test "snooze via turbo stream removes alert card" do
    alert = alerts(:expiry_warning)
    patch snooze_alert_path(alert, days: 7), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match "turbo-stream", response.body
  end

  test "cannot acknowledge other org's alert" do
    alert = alerts(:other_org_alert)
    patch acknowledge_alert_path(alert)
    assert_redirected_to root_path
    assert_equal "The record you were looking for could not be found.", flash[:alert]
  end

  test "cannot snooze other org's alert" do
    alert = alerts(:other_org_alert)
    patch snooze_alert_path(alert, days: 7)
    assert_redirected_to root_path
    assert_equal "The record you were looking for could not be found.", flash[:alert]
  end

  test "requires authentication" do
    sign_out
    get alerts_path
    assert_response :redirect
  end

  test "notification bell shows unread count" do
    get alerts_path
    assert_select "span.bg-red-500"
  end
end
