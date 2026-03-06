class ContractExtractionsController < ApplicationController
  before_action :set_contract
  before_action :enforce_extraction_limit!, only: :create

  def create
    if @contract.contract_documents.completed.none?
      redirect_to @contract, alert: "No extracted documents available. Upload a document first."
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
    if @contract.contract_documents.completed.none?
      redirect_to @contract, alert: "No extracted documents available. Upload a document first."
      return
    end

    # Build document text and run lease type detection
    service = ContractAiExtractorService.new(@contract)
    document_text = service.send(:build_document_text)
    prior_type = @contract.contract_type

    # Temporarily clear contract_type to allow re-detection
    @contract.update_column(:contract_type, nil)
    @contract.reload

    detected = service.send(:detect_and_set_lease_type!, document_text)
    @contract.reload

    if detected
      log_audit("updated", contract: @contract, details: "Re-detected contract type as '#{@contract.contract_type}' (was '#{prior_type}')")
      redirect_to @contract, notice: "Contract type re-detected as \"#{@contract.contract_type.titleize}\" based on document content."
    else
      # Restore prior type if detection found nothing
      @contract.update_column(:contract_type, prior_type)
      redirect_to @contract, notice: "No specific contract type could be detected from the document content. Type remains \"#{prior_type&.titleize || 'unset'}\"."
    end
  end

  private

  def set_contract
    @contract = Contract.find(params[:contract_id])
  end
end
