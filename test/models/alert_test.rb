require "test_helper"

class AlertTest < ActiveSupport::TestCase
  setup do
    @alert = alerts(:expiry_warning)
  end

  # Validations
  test "valid alert" do
    assert @alert.valid?
  end

  test "requires alert_type" do
    @alert.alert_type = nil
    assert_not @alert.valid?
  end

  test "requires trigger_date" do
    @alert.trigger_date = nil
    assert_not @alert.valid?
  end

  test "validates alert_type inclusion" do
    @alert.alert_type = "invalid"
    assert_not @alert.valid?
  end

  test "validates status inclusion" do
    @alert.status = "invalid"
    assert_not @alert.valid?
  end

  # Associations
  test "belongs to contract" do
    assert_equal contracts(:landscaping), @alert.contract
  end

  test "belongs to organization" do
    assert_equal organizations(:one), @alert.organization
  end

  test "has many alert_recipients" do
    assert @alert.alert_recipients.count >= 1
  end

  # Scopes
  test "pending scope" do
    pending = Alert.pending
    assert_includes pending, alerts(:expiry_warning)
    assert_not_includes pending, alerts(:acknowledged_alert)
  end

  test "sent scope" do
    sent = Alert.sent
    assert_includes sent, alerts(:sent_alert)
    assert_not_includes sent, alerts(:expiry_warning)
  end

  test "unacknowledged scope includes pending and sent" do
    unacknowledged = Alert.unacknowledged
    assert_includes unacknowledged, alerts(:expiry_warning)
    assert_includes unacknowledged, alerts(:sent_alert)
    assert_not_includes unacknowledged, alerts(:acknowledged_alert)
    assert_not_includes unacknowledged, alerts(:snoozed_alert)
  end

  test "due_today scope" do
    today = Alert.due_today
    assert_includes today, alerts(:expiry_warning)
    assert_not_includes today, alerts(:renewal_upcoming)
  end

  test "overdue scope returns pending alerts with past trigger dates" do
    overdue = Alert.overdue
    assert_includes overdue, alerts(:overdue_alert)
    assert_not_includes overdue, alerts(:renewal_upcoming) # future
    assert_not_includes overdue, alerts(:acknowledged_alert) # past but acknowledged
  end

  test "upcoming scope returns future alerts within 90 days" do
    upcoming = Alert.upcoming
    assert_includes upcoming, alerts(:renewal_upcoming)
    assert_not_includes upcoming, alerts(:expiry_warning) # today
    assert_not_includes upcoming, alerts(:overdue_alert) # past
    assert_not_includes upcoming, alerts(:scheduled_far_future) # beyond 90 days
  end

  test "scheduled scope returns alerts beyond 90 days" do
    scheduled = Alert.scheduled
    assert_includes scheduled, alerts(:scheduled_far_future)
    assert_not_includes scheduled, alerts(:renewal_upcoming) # within 90 days
    assert_not_includes scheduled, alerts(:expiry_warning) # today
    assert_not_includes scheduled, alerts(:overdue_alert) # past
  end

  test "actionable scope returns alerts within 90 days including overdue and today" do
    actionable = Alert.actionable
    assert_includes actionable, alerts(:expiry_warning) # today
    assert_includes actionable, alerts(:overdue_alert) # past
    assert_includes actionable, alerts(:renewal_upcoming) # within 90 days
    assert_not_includes actionable, alerts(:scheduled_far_future) # beyond 90 days
  end

  test "due_on_or_before scope" do
    results = Alert.due_on_or_before(Date.current)
    assert_includes results, alerts(:expiry_warning)
    assert_includes results, alerts(:overdue_alert)
    assert_not_includes results, alerts(:renewal_upcoming)
  end

  test "for_user scope" do
    user_one_alerts = Alert.for_user(users(:one))
    assert_includes user_one_alerts, alerts(:expiry_warning)
    assert_not_includes user_one_alerts, alerts(:other_org_alert)
  end

  # Methods
  test "acknowledge! marks current user's recipient as read" do
    user = users(:one)
    @alert.acknowledge!(user: user)
    recipient = @alert.alert_recipients.find_by(user: user)
    assert_not_nil recipient.read_at
  end

  test "acknowledge! transitions alert to acknowledged when all recipients read" do
    user = users(:one)
    @alert.acknowledge!(user: user)
    assert_equal "acknowledged", @alert.reload.status
  end

  test "acknowledge! does not transition alert when other recipients unread" do
    user_one = users(:one)
    org = organizations(:one)
    # Add a second recipient
    user_two = users(:two)
    Membership.find_or_create_by!(user: user_two, organization: org) { |m| m.role = "member" }
    @alert.alert_recipients.create!(user: user_two, channel: "email")

    @alert.acknowledge!(user: user_one)
    assert_not_equal "acknowledged", @alert.reload.status
    assert_nil @alert.alert_recipients.find_by(user: user_two).read_at
  end

  test "acknowledge! transitions to acknowledged after all recipients read" do
    user_one = users(:one)
    org = organizations(:one)
    user_two = users(:two)
    Membership.find_or_create_by!(user: user_two, organization: org) { |m| m.role = "member" }
    @alert.alert_recipients.create!(user: user_two, channel: "email")

    @alert.acknowledge!(user: user_one)
    assert_not_equal "acknowledged", @alert.reload.status

    @alert.acknowledge!(user: user_two)
    assert_equal "acknowledged", @alert.reload.status
  end

  test "acknowledge! is idempotent on already-read recipients" do
    user = users(:one)
    @alert.acknowledge!(user: user)
    original_read_at = @alert.alert_recipients.find_by(user: user).read_at
    @alert.acknowledge!(user: user)
    # read_at should not change
    assert_equal original_read_at, @alert.alert_recipients.find_by(user: user).read_at
  end

  test "snooze! sets snoozed_until on current user's recipient" do
    user = users(:one)
    @alert.snooze!(user: user, days: 7)
    recipient = @alert.alert_recipients.find_by(user: user)
    assert_equal Date.current + 7.days, recipient.snoozed_until
  end

  test "snooze! does not affect other users' recipients" do
    user_one = users(:one)
    org = organizations(:one)
    user_two = users(:two)
    Membership.find_or_create_by!(user: user_two, organization: org) { |m| m.role = "member" }
    @alert.alert_recipients.create!(user: user_two, channel: "email")

    @alert.snooze!(user: user_one, days: 7)
    assert_nil @alert.alert_recipients.find_by(user: user_two).snoozed_until
  end

  test "snooze! does not change alert-level trigger_date or status" do
    original_date = @alert.trigger_date
    original_status = @alert.status
    @alert.snooze!(user: users(:one), days: 7)
    assert_equal original_date, @alert.reload.trigger_date
    assert_equal original_status, @alert.status
  end

  test "overdue? returns true for past trigger dates" do
    @alert.trigger_date = 2.days.ago.to_date
    assert @alert.overdue?
  end

  test "overdue? returns false for today" do
    @alert.trigger_date = Date.current
    assert_not @alert.overdue?
  end

  test "overdue? returns false for acknowledged alerts" do
    @alert.trigger_date = 2.days.ago.to_date
    @alert.status = "acknowledged"
    assert_not @alert.overdue?
  end

  test "due_today? returns true for today" do
    @alert.trigger_date = Date.current
    assert @alert.due_today?
  end

  test "due_today? returns false for other dates" do
    @alert.trigger_date = 1.day.ago.to_date
    assert_not @alert.due_today?
    @alert.trigger_date = 1.day.from_now.to_date
    assert_not @alert.due_today?
  end

  test "alert_type_label returns human-readable label" do
    assert_equal "Expiry Warning", @alert.alert_type_label
    @alert.alert_type = "renewal_upcoming"
    assert_equal "Renewal Upcoming", @alert.alert_type_label
  end

  # scheduled?
  test "scheduled? returns true for alerts beyond 90 days" do
    @alert.trigger_date = (Date.current + 91).to_date
    @alert.status = "pending"
    assert @alert.scheduled?
  end

  test "scheduled? returns false for alerts within 90 days" do
    @alert.trigger_date = 30.days.from_now.to_date
    assert_not @alert.scheduled?
  end

  test "scheduled? returns false for acknowledged alerts" do
    @alert.trigger_date = (Date.current + 91).to_date
    @alert.status = "acknowledged"
    assert_not @alert.scheduled?
  end

  # visible_to scope
  test "visible_to excludes read alerts" do
    user = users(:one)
    @alert.acknowledge!(user: user)
    assert_not_includes Alert.visible_to(user), @alert
  end

  test "visible_to excludes snoozed alerts" do
    user = users(:one)
    @alert.snooze!(user: user, days: 7)
    assert_not_includes Alert.visible_to(user), @alert
  end

  test "visible_to includes alert snoozed until today" do
    user = users(:one)
    @alert.alert_recipients.find_by(user: user).update!(snoozed_until: Date.current)
    assert_includes Alert.visible_to(user), @alert
  end

  # display_message
  test "display_message for upcoming expiry_warning" do
    @alert.trigger_date = 10.days.from_now.to_date
    msg = @alert.display_message
    assert_match "expires in 10 days", msg
    assert_match @alert.contract.title, msg
  end

  test "display_message for overdue expiry_warning" do
    @alert.trigger_date = 3.days.ago.to_date
    msg = @alert.display_message
    assert_match "expired 3 days ago", msg
  end

  test "display_message for due_today expiry_warning" do
    @alert.trigger_date = Date.current
    msg = @alert.display_message
    assert_match "expires today", msg
  end

  test "display_message for scheduled expiry_warning" do
    @alert.trigger_date = 200.days.from_now.to_date
    msg = @alert.display_message
    assert_match "expires on", msg
    assert_match "(in", msg
  end

  test "display_message for upcoming renewal_upcoming" do
    alert = alerts(:renewal_upcoming)
    alert.trigger_date = 5.days.from_now.to_date
    msg = alert.display_message
    assert_match "renews in 5 days", msg
  end

  test "display_message for notice_period_start" do
    alert = Alert.new(
      alert_type: "notice_period_start",
      trigger_date: 15.days.from_now.to_date,
      status: "pending",
      contract: contracts(:hvac_maintenance),
      organization: organizations(:one)
    )
    msg = alert.display_message
    assert_match "Notice period", msg
    assert_match "starts in 15 days", msg
    assert_match "30 days before", msg
  end

  test "display_message for scheduled notice_period_start shows date" do
    alert = Alert.new(
      alert_type: "notice_period_start",
      trigger_date: 200.days.from_now.to_date,
      status: "pending",
      contract: contracts(:hvac_maintenance),
      organization: organizations(:one)
    )
    msg = alert.display_message
    assert_match "Notice period", msg
    assert_match "starts on", msg
  end

  test "destroying alert cascades to recipients" do
    assert @alert.alert_recipients.any?
    recipient_ids = @alert.alert_recipient_ids
    @alert.destroy!
    assert_equal 0, AlertRecipient.where(id: recipient_ids).count
  end
end
