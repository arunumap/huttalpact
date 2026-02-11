require "test_helper"

class AlertRecipientTest < ActiveSupport::TestCase
  setup do
    @recipient = alert_recipients(:one_expiry)
  end

  test "valid alert_recipient" do
    assert @recipient.valid?
  end

  test "validates channel inclusion" do
    @recipient.channel = "sms"
    assert_not @recipient.valid?
  end

  test "belongs to alert" do
    assert_equal alerts(:expiry_warning), @recipient.alert
  end

  test "belongs to user" do
    assert_equal users(:one), @recipient.user
  end

  # Scopes
  test "unread scope" do
    unread = AlertRecipient.unread
    assert_includes unread, alert_recipients(:one_expiry)
    assert_not_includes unread, alert_recipients(:one_acknowledged)
  end

  test "unsent scope" do
    unsent = AlertRecipient.unsent
    assert_includes unsent, alert_recipients(:one_expiry)
    assert_not_includes unsent, alert_recipients(:one_sent)
  end

  test "for_user scope" do
    user_one = AlertRecipient.for_user(users(:one))
    assert_includes user_one, alert_recipients(:one_expiry)
    assert_not_includes user_one, alert_recipients(:two_alert)
  end

  # Methods
  test "read? returns false when read_at is nil" do
    assert_not @recipient.read?
  end

  test "read? returns true when read_at is set" do
    assert alert_recipients(:one_acknowledged).read?
  end

  test "sent? returns false when sent_at is nil" do
    assert_not @recipient.sent?
  end

  test "sent? returns true when sent_at is set" do
    assert alert_recipients(:one_sent).sent?
  end

  test "mark_as_read! sets read_at" do
    assert_nil @recipient.read_at
    @recipient.mark_as_read!
    assert_not_nil @recipient.reload.read_at
  end

  test "mark_as_read! is idempotent" do
    @recipient.mark_as_read!
    original_read_at = @recipient.reload.read_at
    @recipient.mark_as_read!
    assert_equal original_read_at, @recipient.reload.read_at
  end

  test "mark_as_sent! sets sent_at" do
    assert_nil @recipient.sent_at
    @recipient.mark_as_sent!
    assert_not_nil @recipient.reload.sent_at
  end

  test "mark_as_sent! is idempotent" do
    @recipient.mark_as_sent!
    original_sent_at = @recipient.reload.sent_at
    @recipient.mark_as_sent!
    assert_equal original_sent_at, @recipient.reload.sent_at
  end

  test "uniqueness constraint on alert_id and user_id" do
    dup = AlertRecipient.new(
      alert: @recipient.alert,
      user: @recipient.user,
      channel: "in_app"
    )
    assert_not dup.valid?
  end
end
