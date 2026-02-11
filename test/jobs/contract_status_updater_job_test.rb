require "test_helper"

class ContractStatusUpdaterJobTest < ActiveJob::TestCase
  test "expires contracts past end_date" do
    contract = contracts(:hvac_maintenance)
    contract.update_columns(status: "active", end_date: 1.day.ago.to_date)

    ContractStatusUpdaterJob.perform_now

    assert_equal "expired", contract.reload.status
  end

  test "expires contracts ending exactly today" do
    contract = contracts(:hvac_maintenance)
    contract.update_columns(status: "active", end_date: Date.current)

    ContractStatusUpdaterJob.perform_now

    assert_equal "expired", contract.reload.status
  end

  test "marks contracts expiring within 30 days as expiring_soon" do
    contract = contracts(:hvac_maintenance)
    contract.update_columns(status: "active", end_date: 15.days.from_now.to_date)

    ContractStatusUpdaterJob.perform_now

    assert_equal "expiring_soon", contract.reload.status
  end

  test "marks contracts expiring at exactly 30 days as expiring_soon" do
    contract = contracts(:hvac_maintenance)
    contract.update_columns(status: "active", end_date: 30.days.from_now.to_date)

    ContractStatusUpdaterJob.perform_now

    assert_equal "expiring_soon", contract.reload.status
  end

  test "does not change contracts expiring at 31 days" do
    contract = contracts(:hvac_maintenance)
    contract.update_columns(status: "active", end_date: 31.days.from_now.to_date)

    ContractStatusUpdaterJob.perform_now

    assert_equal "active", contract.reload.status
  end

  test "does not change contracts expiring beyond 30 days" do
    contract = contracts(:hvac_maintenance)
    contract.update_columns(status: "active", end_date: 60.days.from_now.to_date)

    ContractStatusUpdaterJob.perform_now

    assert_equal "active", contract.reload.status
  end

  test "does not change already expired contracts" do
    contract = contracts(:expired_insurance)

    ContractStatusUpdaterJob.perform_now

    assert_equal "expired", contract.reload.status
  end

  test "does not change cancelled contracts" do
    contract = contracts(:hvac_maintenance)
    contract.update_columns(status: "cancelled", end_date: 1.day.ago.to_date)

    ContractStatusUpdaterJob.perform_now

    assert_equal "cancelled", contract.reload.status
  end

  test "does not change renewed contracts" do
    contract = contracts(:hvac_maintenance)
    contract.update_columns(status: "renewed", end_date: 1.day.ago.to_date)

    ContractStatusUpdaterJob.perform_now

    assert_equal "renewed", contract.reload.status
  end

  test "cancels pending alerts when contract expires" do
    contract = contracts(:hvac_maintenance)
    contract.update_columns(status: "active", end_date: 1.day.ago.to_date)

    alert = Alert.create!(
      organization: contract.organization,
      contract: contract,
      alert_type: "expiry_warning",
      trigger_date: 2.days.ago.to_date,
      status: "pending",
      message: "Test alert"
    )

    ContractStatusUpdaterJob.perform_now

    assert_equal "cancelled", alert.reload.status
  end

  test "cancels snoozed alerts when contract expires" do
    contract = contracts(:hvac_maintenance)
    contract.update_columns(status: "active", end_date: 1.day.ago.to_date)

    alert = Alert.create!(
      organization: contract.organization,
      contract: contract,
      alert_type: "expiry_warning",
      trigger_date: 2.days.ago.to_date,
      status: "snoozed",
      message: "Test snoozed alert"
    )

    ContractStatusUpdaterJob.perform_now

    assert_equal "cancelled", alert.reload.status
  end

  test "does not cancel sent alerts when contract expires" do
    contract = contracts(:hvac_maintenance)
    contract.update_columns(status: "active", end_date: 1.day.ago.to_date)

    alert = Alert.create!(
      organization: contract.organization,
      contract: contract,
      alert_type: "expiry_warning",
      trigger_date: 5.days.ago.to_date,
      status: "sent",
      message: "Test sent alert"
    )

    ContractStatusUpdaterJob.perform_now

    assert_equal "sent", alert.reload.status
  end
end
