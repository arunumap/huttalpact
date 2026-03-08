require "test_helper"

class AlertGeneratorServiceTest < ActiveSupport::TestCase
  setup do
    @contract = contracts(:hvac_maintenance)
    @organization = organizations(:one)
  end

  test "generates expiry alerts when end_date is set" do
    @contract.alerts.destroy_all
    AlertGeneratorService.new(@contract).call
    assert Alert.where(contract: @contract, alert_type: "expiry_warning").exists?,
           "Should have created an expiry_warning alert"
  end

  test "generates renewal alerts when next_renewal_date is set" do
    # Clear existing alerts for a clean slate
    @contract.alerts.destroy_all
    AlertGeneratorService.new(@contract).call
    assert Alert.where(contract: @contract, alert_type: "renewal_upcoming").exists?,
           "Should have created a renewal_upcoming alert"
  end

  test "generates notice period alerts when notice_period_days is set" do
    # Clear existing alerts so already_alerted? doesn't skip
    @contract.alerts.destroy_all
    AlertGeneratorService.new(@contract).call
    assert Alert.where(contract: @contract, alert_type: "notice_period_start").exists?,
           "Should have created a notice_period_start alert"
  end

  test "skips expired contracts" do
    expired = contracts(:expired_insurance)
    assert_no_difference "Alert.count" do
      AlertGeneratorService.new(expired).call
    end
  end

  test "skips cancelled contracts" do
    @contract.update!(status: "cancelled")
    @contract.alerts.destroy_all
    assert_no_difference "Alert.count" do
      AlertGeneratorService.new(@contract).call
    end
  end

  test "skips in_review contracts without mutating existing alerts" do
    @contract.update!(status: "in_review")
    @contract.alerts.destroy_all

    existing_alert = @contract.alerts.create!(
      organization: @organization,
      alert_type: "expiry_warning",
      trigger_date: 10.days.from_now,
      status: "pending",
      message: "Keep me"
    )

    assert_no_difference "Alert.count" do
      AlertGeneratorService.new(@contract).call
    end

    assert Alert.exists?(existing_alert.id), "Existing alert should be preserved while contract is in review"
  end

  test "skips contracts without relevant dates" do
    # Clear existing alerts first so clear_regenerable_alerts! doesn't affect count
    @contract.alerts.destroy_all
    @contract.update!(end_date: nil, next_renewal_date: nil, notice_period_days: nil)
    assert_no_difference "Alert.count" do
      AlertGeneratorService.new(@contract.reload).call
    end
  end

  test "skips contracts with end_date in the past" do
    @contract.alerts.destroy_all
    @contract.update!(end_date: 1.day.ago, next_renewal_date: nil, notice_period_days: nil)
    assert_no_difference "Alert.count" do
      AlertGeneratorService.new(@contract.reload).call
    end
  end

  test "skips contracts with next_renewal_date in the past" do
    @contract.alerts.destroy_all
    @contract.update!(end_date: nil, next_renewal_date: 1.day.ago, notice_period_days: nil)
    assert_no_difference "Alert.count" do
      AlertGeneratorService.new(@contract.reload).call
    end
  end

  test "clears pending alerts before regenerating" do
    # Create a pending alert
    alert = @contract.alerts.create!(
      organization: @organization,
      alert_type: "expiry_warning",
      trigger_date: 10.days.from_now,
      status: "pending",
      message: "Old alert"
    )

    AlertGeneratorService.new(@contract).call

    assert_not Alert.exists?(alert.id), "Old pending alert should be destroyed"
  end

  test "clears snoozed alerts before regenerating" do
    snoozed = alerts(:snoozed_alert)
    assert_equal "snoozed", snoozed.status

    AlertGeneratorService.new(snoozed.contract).call

    assert_not Alert.exists?(snoozed.id), "Snoozed alert should be destroyed"
  end

  test "does not clear acknowledged alerts" do
    acknowledged = alerts(:acknowledged_alert)
    AlertGeneratorService.new(acknowledged.contract).call
    assert Alert.exists?(acknowledged.id), "Acknowledged alert should persist"
  end

  test "does not clear sent alerts" do
    sent = alerts(:sent_alert)
    AlertGeneratorService.new(sent.contract).call
    assert Alert.exists?(sent.id), "Sent alert should persist"
  end

  test "is idempotent - running twice creates same alerts" do
    AlertGeneratorService.new(@contract).call
    count_after_first = Alert.where(contract: @contract).count

    AlertGeneratorService.new(@contract).call
    count_after_second = Alert.where(contract: @contract).count

    # Should not keep accumulating (pending ones cleared and recreated, acknowledged kept)
    assert_equal count_after_first, count_after_second
  end

  test "creates alert recipients for each org member" do
    AlertGeneratorService.new(@contract).call
    alert = Alert.where(contract: @contract, alert_type: "expiry_warning").last
    assert alert.present?, "Should have created an expiry alert"
    assert alert.alert_recipients.any?, "Alert should have recipients"
  end

  test "respects user alert preferences for channels" do
    pref = alert_preferences(:one)
    pref.update!(email_enabled: true, in_app_enabled: false)

    AlertGeneratorService.new(@contract).call
    alert = Alert.where(contract: @contract, alert_type: "expiry_warning").last

    channels = alert.alert_recipients.where(user: users(:one)).pluck(:channel)
    assert_includes channels, "in_app", "Channel should always be in_app — email is handled at delivery time"
  end

  test "creates recipient when both email and in_app are enabled" do
    pref = alert_preferences(:one)
    pref.update!(email_enabled: true, in_app_enabled: true)

    AlertGeneratorService.new(@contract).call
    alert = Alert.where(contract: @contract, alert_type: "expiry_warning").last

    recipients = alert.alert_recipients.where(user: users(:one))
    assert_equal 1, recipients.count, "Should create exactly one recipient per user"
    assert_equal "in_app", recipients.first.channel, "Channel should always be in_app"
  end

  test "uses in_app channel even when email is disabled" do
    pref = alert_preferences(:one)
    pref.update!(email_enabled: false, in_app_enabled: true)

    AlertGeneratorService.new(@contract).call
    alert = Alert.where(contract: @contract, alert_type: "expiry_warning").last

    channels = alert.alert_recipients.where(user: users(:one)).pluck(:channel)
    assert_includes channels, "in_app"
  end

  test "skips recipient when both channels are disabled" do
    pref = alert_preferences(:one)
    pref.update!(email_enabled: false, in_app_enabled: false)

    @contract.alerts.destroy_all
    AlertGeneratorService.new(@contract).call

    # User one should have no recipients on any alert for this contract
    recipient_count = AlertRecipient.joins(:alert)
      .where(alerts: { contract_id: @contract.id }, user_id: users(:one).id)
      .count
    assert_equal 0, recipient_count,
                 "Should not create recipient when both channels are disabled"
  end

  test "uses default preferences when user has no preference" do
    AlertPreference.where(user: users(:one)).destroy_all
    @contract.alerts.destroy_all

    AlertGeneratorService.new(@contract).call

    assert Alert.where(contract: @contract).exists?, "Should create alerts with default preferences"
  end

  test "trigger_date is clamped to today when calculated date is in the past" do
    @contract.alerts.destroy_all
    @contract.update!(end_date: 5.days.from_now.to_date)
    pref = alert_preferences(:one)
    pref.update!(days_before_expiry: 30)

    AlertGeneratorService.new(@contract).call
    alert = Alert.where(contract: @contract, alert_type: "expiry_warning").last

    assert_equal Date.current, alert.trigger_date, "Trigger date should be clamped to today"
  end

  test "already_alerted skips duplicate sent alerts" do
    @contract.alerts.destroy_all
    sent_alert = @contract.alerts.create!(
      organization: @organization,
      alert_type: "expiry_warning",
      trigger_date: 1.day.ago.to_date,
      status: "sent",
      message: "Already sent"
    )
    sent_alert.alert_recipients.create!(user: users(:one), channel: "email")

    pref = alert_preferences(:one)
    pref.update!(days_before_expiry: 30)
    @contract.update!(end_date: 5.days.from_now.to_date)

    AlertGeneratorService.new(@contract).call

    assert_equal 1, Alert.where(contract: @contract, alert_type: "expiry_warning").count
  end

  # --- Lease-specific alert tests ---

  test "generates option_exercise_deadline alerts from lease_options" do
    lease = contracts(:commercial_lease)
    lease.alerts.destroy_all

    AlertGeneratorService.new(lease).call
    alerts = Alert.where(contract: lease, alert_type: "option_exercise_deadline")
    assert alerts.exists?, "Should create option_exercise_deadline alerts for lease options with future notice_deadline"
  end

  test "generates rent_escalation_date alerts from future rent_escalations" do
    lease = contracts(:commercial_lease)
    lease.alerts.destroy_all

    AlertGeneratorService.new(lease).call
    alerts = Alert.where(contract: lease, alert_type: "rent_escalation_date")
    assert alerts.exists?, "Should create rent_escalation_date alerts for future rent escalations"
  end

  test "generates cam_reconciliation alerts from lease_detail" do
    lease = contracts(:commercial_lease)
    lease.alerts.destroy_all
    assert lease.lease_detail.cam_reconciliation_month.present?, "Fixture should have cam_reconciliation_month"

    AlertGeneratorService.new(lease).call
    alerts = Alert.where(contract: lease, alert_type: "cam_reconciliation")
    assert alerts.exists?, "Should create cam_reconciliation alert when cam_reconciliation_month is set"
  end

  test "generates ti_deadline alerts from lease_detail" do
    lease = contracts(:commercial_lease)
    lease.alerts.destroy_all
    assert lease.lease_detail.ti_deadline.present?, "Fixture should have ti_deadline"
    assert lease.lease_detail.ti_deadline > Date.current, "TI deadline should be in the future"

    AlertGeneratorService.new(lease).call
    alerts = Alert.where(contract: lease, alert_type: "ti_deadline")
    assert alerts.exists?, "Should create ti_deadline alert when ti_deadline is set and future"
  end

  test "generates milestone_reminder alerts from lease_milestones" do
    lease = contracts(:commercial_lease)
    lease.alerts.destroy_all
    future_milestones = lease.lease_milestones.select { |m| (m.recurring? ? m.next_occurrence_date : m.due_date) > Date.current }
    assert future_milestones.any?, "Fixture should have future milestones"

    AlertGeneratorService.new(lease).call
    alerts = Alert.where(contract: lease, alert_type: "milestone_reminder")
    assert alerts.exists?, "Should create milestone_reminder alerts for future milestones"
  end

  test "recurring milestones generate alerts for next occurrence" do
    lease = contracts(:commercial_lease)
    lease.alerts.destroy_all
    recurring = lease.lease_milestones.recurring.first
    assert recurring.present?, "Fixture should have a recurring milestone"

    AlertGeneratorService.new(lease).call
    alerts = Alert.where(contract: lease, alert_type: "milestone_reminder")
    assert alerts.exists?, "Should create milestone alerts for recurring milestones"
  end

  test "does not generate lease alerts for non-lease contracts" do
    @contract.alerts.destroy_all
    refute @contract.lease?, "HVAC contract should not be a lease"

    AlertGeneratorService.new(@contract).call

    assert_equal 0, Alert.where(contract: @contract, alert_type: "option_exercise_deadline").count
    assert_equal 0, Alert.where(contract: @contract, alert_type: "rent_escalation_date").count
    assert_equal 0, Alert.where(contract: @contract, alert_type: "cam_reconciliation").count
    assert_equal 0, Alert.where(contract: @contract, alert_type: "ti_deadline").count
    assert_equal 0, Alert.where(contract: @contract, alert_type: "milestone_reminder").count
  end
end
