class ContractExtractionsController < ApplicationController
  before_action :set_contract
  before_action :enforce_extraction_limit!, only: %i[create confirm_type]

  def create
    if @contract.in_review?
      redirect_to contract_contract_review_path(@contract),
                  alert: "Cannot re-extract while a review is in progress. Complete or discard the current review first."
      return
    end

    if @contract.contract_documents.completed.none?
      redirect_to @contract, alert: "No extracted documents available. Upload a document first."
      return
    end

    if @contract.contract_type.blank?
      redirect_to edit_contract_path(@contract), alert: "Please choose a contract type before running extraction."
      return
    end

    # Reset extraction status and re-run (clauses are destroyed atomically inside the service)
    @contract.update!(extraction_status: "pending")

    AiExtractContractJob.perform_later(@contract.id)
    log_audit("updated", contract: @contract, details: "Triggered AI re-extraction")

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "contract_ai_status",
          partial: "contracts/ai_status",
          locals: { contract: @contract, status_override: "processing" }
        )
      end
      format.html { redirect_to @contract, notice: "AI extraction started. Results will appear shortly." }
    end
  end

  def redetect
    redirect_to edit_contract_path(@contract), alert: "Auto-detect has been retired. Please choose the contract type explicitly and re-extract."
  end

  def confirm_type
    if @contract.in_review?
      redirect_to contract_contract_review_path(@contract),
                  alert: "Cannot change contract type while a review is in progress."
      return
    end

    if @contract.contract_documents.completed.none?
      redirect_to @contract, alert: "No extracted documents available. Upload a document first."
      return
    end

    selected_type = params[:contract_type].to_s
    unless Contract::CONTRACT_TYPES.include?(selected_type)
      redirect_to edit_contract_path(@contract), alert: "Please choose a valid contract type."
      return
    end

    @contract.update!(
      contract_type: selected_type,
      extraction_status: "pending"
    )

    AiExtractContractJob.perform_later(@contract.id)
    log_audit("updated", contract: @contract, details: "Contract type set to '#{selected_type}' and AI extraction triggered")

    destination = @contract.draft? ? edit_contract_path(@contract) : contract_path(@contract)
    redirect_to destination, notice: "Contract type set to \"#{selected_type.titleize.gsub('_', ' ')}\". AI extraction started."
  end

  private

  def set_contract
    @contract = Contract.find(params[:contract_id])
  end
end
