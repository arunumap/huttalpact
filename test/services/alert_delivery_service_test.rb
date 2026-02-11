require "test_helper"

class AlertDeliveryServiceTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @alert = alerts(:expiry_warning)
  end

  test "delivers to unsent email recipients" do
    assert_enqueued_emails 1 do
      AlertDeliveryService.new(@alert).call
    end
  end

  test "marks recipients as sent" do
    AlertDeliveryService.new(@alert).call
    @alert.alert_recipients.each do |recipient|
      assert recipient.reload.sent?, "Recipient should be marked as sent"
    end
  end

  test "updates alert status to sent" do
    AlertDeliveryService.new(@alert).call
    assert_equal "sent", @alert.reload.status
  end

  test "skips non-pending alerts" do
    @alert.update!(status: "acknowledged")
    assert_no_enqueued_emails do
      AlertDeliveryService.new(@alert).call
    end
    assert_equal "acknowledged", @alert.reload.status
  end

  test "skips already-sent recipients" do
    @alert.alert_recipients.update_all(sent_at: Time.current)
    assert_no_enqueued_emails do
      AlertDeliveryService.new(@alert).call
    end
  end

  test "respects email_enabled preference" do
    pref = alert_preferences(:one)
    pref.update!(email_enabled: false)

    assert_no_enqueued_emails do
      AlertDeliveryService.new(@alert).call
    end
    # Status still transitions to sent even if email was suppressed
    assert_equal "sent", @alert.reload.status
  end

  test "handles in_app channel without sending email" do
    @alert.alert_recipients.update_all(channel: "in_app")
    assert_no_enqueued_emails do
      AlertDeliveryService.new(@alert).call
    end
    assert_equal "sent", @alert.reload.status
  end

  test "handles delivery error without stopping" do
    AlertMailer.stub(:alert_notification, ->(_) { raise "SMTP error" }) do
      # Should not raise — errors are rescued per-recipient
      assert_nothing_raised do
        AlertDeliveryService.new(@alert).call
      end
    end
  end

  test "skips delivery for expired contract and cancels alert" do
    @alert.contract.update_columns(status: "expired")

    assert_no_enqueued_emails do
      AlertDeliveryService.new(@alert).call
    end
    assert_equal "cancelled", @alert.reload.status
  end

  test "skips delivery for cancelled contract and cancels alert" do
    @alert.contract.update_columns(status: "cancelled")

    assert_no_enqueued_emails do
      AlertDeliveryService.new(@alert).call
    end
    assert_equal "cancelled", @alert.reload.status
  end
end
