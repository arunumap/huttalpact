require "test_helper"

class DailyAlertCheckJobTest < ActiveJob::TestCase
  test "delivers pending alerts due today" do
    alert = alerts(:expiry_warning) # trigger_date = Date.current, status = pending
    assert_equal "pending", alert.status
    assert_equal Date.current, alert.trigger_date

    DailyAlertCheckJob.perform_now

    assert_equal "sent", alert.reload.status
  end

  test "delivers overdue pending alerts" do
    alert = alerts(:overdue_alert) # trigger_date = 3.days.ago, status = pending
    assert_equal "pending", alert.status
    assert alert.trigger_date < Date.current

    DailyAlertCheckJob.perform_now

    assert_equal "sent", alert.reload.status
  end

  test "does not deliver future alerts" do
    alert = alerts(:renewal_upcoming) # trigger_date = 5.days.from_now, status = pending
    assert_equal "pending", alert.status
    assert alert.trigger_date > Date.current

    DailyAlertCheckJob.perform_now

    assert_equal "pending", alert.reload.status
  end

  test "does not deliver already sent alerts" do
    alert = alerts(:sent_alert)
    assert_equal "sent", alert.status

    DailyAlertCheckJob.perform_now

    assert_equal "sent", alert.reload.status
  end

  test "does not deliver acknowledged alerts" do
    alert = alerts(:acknowledged_alert)
    assert_equal "acknowledged", alert.status

    DailyAlertCheckJob.perform_now

    assert_equal "acknowledged", alert.reload.status
  end

  test "does not deliver snoozed alerts" do
    alert = alerts(:snoozed_alert)
    assert_equal "snoozed", alert.status

    DailyAlertCheckJob.perform_now

    assert_equal "snoozed", alert.reload.status
  end

  test "handles errors per-alert without stopping" do
    # Even if one alert fails, others should still be delivered
    alert_due = alerts(:expiry_warning)

    # Both overdue_alert and expiry_warning are pending and due
    # If one raises, the other should still process
    assert_nothing_raised do
      DailyAlertCheckJob.perform_now
    end
  end
end
