class ContractExtractionsController < ApplicationController
  before_action :set_contract
  before_action :enforce_extraction_limit!

  def create
    if @contract.contract_documents.completed.none?
      redirect_to @contract, alert: "No extracted documents available. Upload a document first."
      return
    end

    # Reset extraction status and re-run (clauses are destroyed atomically inside the service)
    @contract.update!(extraction_status: "pending")

    AiExtractContractJob.perform_later(@contract.id)
    log_audit("updated", contract: @contract, details: "Triggered AI re-extraction")

    redirect_to @contract, notice: "AI extraction started. Results will appear shortly."
  end

  private

  def set_contract
    @contract = Contract.find(params[:contract_id])
  end
end
