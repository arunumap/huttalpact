class GenerateContractAlertsJob < ApplicationJob
  queue_as :default

  def perform(contract_id)
    contract = Contract.find(contract_id)
    AlertGeneratorService.new(contract).call
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn("Contract #{contract_id} not found, skipping alert generation")
  end
end
