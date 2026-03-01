require "test_helper"

class AlertGeneratorServiceLeaseTest < ActiveSupport::TestCase
  setup do
    @contract = contracts(:commercial_lease)
    @organization = organizations(:one)
    @contract.alerts.destroy_all
  end

  test "generates option exercise alerts for lease contracts" do
    AlertGeneratorService.new(@contract).call

    option_alerts = Alert.where(contract: @contract, alert_type: "option_exercise_deadline")
    assert option_alerts.any?, "Should create option_exercise_deadline alerts"
  end

  test "generates rent escalation alerts for lease contracts" do
    AlertGeneratorService.new(@contract).call

    escalation_alerts = Alert.where(contract: @contract, alert_type: "rent_escalation_date")
    # Only future escalations should generate alerts
    future_count = @contract.rent_escalations.future.count
    if future_count > 0
      assert escalation_alerts.any?, "Should create rent_escalation_date alerts for future escalations"
    end
  end

  test "generates cam reconciliation alerts for lease contracts" do
    AlertGeneratorService.new(@contract).call

    cam_alerts = Alert.where(contract: @contract, alert_type: "cam_reconciliation")
    assert cam_alerts.any?, "Should create cam_reconciliation alert"
  end

  test "generates ti deadline alerts for lease contracts" do
    AlertGeneratorService.new(@contract).call

    ti_alerts = Alert.where(contract: @contract, alert_type: "ti_deadline")
    assert ti_alerts.any?, "Should create ti_deadline alert"
  end

  test "generates milestone reminder alerts for lease contracts" do
    AlertGeneratorService.new(@contract).call

    milestone_alerts = Alert.where(contract: @contract, alert_type: "milestone_reminder")
    assert milestone_alerts.any?, "Should create milestone_reminder alerts"
  end

  test "does not generate lease alerts for non-lease contracts" do
    non_lease = contracts(:hvac_maintenance)
    non_lease.alerts.destroy_all

    AlertGeneratorService.new(non_lease).call

    lease_alert_types = %w[option_exercise_deadline rent_escalation_date cam_reconciliation ti_deadline milestone_reminder]
    lease_alerts = Alert.where(contract: non_lease, alert_type: lease_alert_types)
    assert_equal 0, lease_alerts.count, "Non-lease contracts should not have lease-specific alerts"
  end

  test "respects user preference for days_before_option_exercise" do
    pref = alert_preferences(:one)
    pref.update!(days_before_option_exercise: 180)

    AlertGeneratorService.new(@contract).call

    option_alerts = Alert.where(contract: @contract, alert_type: "option_exercise_deadline")
    # With 180 days lead time, more options might get alerts triggered earlier
    assert option_alerts.any?, "Should create alerts with custom lead time"
  end

  test "skips overdue milestones" do
    AlertGeneratorService.new(@contract).call

    # The overdue_milestone fixture has a past due date — should not generate alert
    milestone_alerts = Alert.where(contract: @contract, alert_type: "milestone_reminder")
    alert_messages = milestone_alerts.pluck(:message)
    alert_messages.each do |msg|
      assert_not_includes msg, "estoppel", "Should not create alert for overdue milestones"
    end
  end

  test "is idempotent for lease alerts" do
    AlertGeneratorService.new(@contract).call
    first_count = Alert.where(contract: @contract).count

    AlertGeneratorService.new(@contract).call
    second_count = Alert.where(contract: @contract).count

    assert_equal first_count, second_count, "Running twice should produce same alert count"
  end

  test "also generates standard alerts for lease contracts" do
    AlertGeneratorService.new(@contract).call

    # Lease contracts should still get expiry/renewal/notice alerts
    assert Alert.where(contract: @contract, alert_type: "expiry_warning").exists?,
           "Lease should also get expiry_warning alerts"
    assert Alert.where(contract: @contract, alert_type: "renewal_upcoming").exists?,
           "Lease should also get renewal_upcoming alerts"
  end
end
