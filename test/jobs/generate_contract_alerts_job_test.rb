require "test_helper"

class GenerateContractAlertsJobTest < ActiveJob::TestCase
  test "calls AlertGeneratorService" do
    contract = contracts(:hvac_maintenance)

    # Service clears pending/snoozed and recreates, so just verify it runs without error
    # and generates alerts for the contract
    assert_nothing_raised do
      GenerateContractAlertsJob.perform_now(contract.id)
    end
    assert Alert.where(contract: contract, status: "pending").exists?
  end

  test "handles missing contract gracefully" do
    assert_nothing_raised do
      GenerateContractAlertsJob.perform_now("nonexistent-uuid")
    end
  end
end
