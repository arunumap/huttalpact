class AiExtractContractJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ContractAiExtractorService::ExtractionError
  discard_on ContractAiExtractorService::ExtractionLimitReachedError

  # new_document_id: when provided, triggers incremental mode (addendum/amendment uploaded)
  # when nil, triggers full mode (initial extraction or manual re-extract)
  def perform(contract_id, new_document_id: nil)
    contract = Contract.find(contract_id)

    mode = new_document_id.present? ? :incremental : :full
    ContractAiExtractorService.new(contract, mode: mode, new_document_id: new_document_id).call

    # Broadcast updated contract show page
    contract.reload
    broadcast_contract_update(contract)
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn("Contract #{contract_id} not found, skipping AI extraction")
  rescue => e
    # On failure, still broadcast status update so draft UI reflects the failure
    contract&.reload
    broadcast_contract_update(contract) if contract
    raise e
  end

  private

  def broadcast_contract_update(contract)
    Turbo::StreamsChannel.broadcast_replace_to(
      "contract_#{contract.id}",
      target: "contract_ai_status",
      partial: "contracts/ai_status",
      locals: { contract: contract }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      "contract_#{contract.id}",
      target: "contract_key_clauses",
      partial: "contracts/key_clauses",
      locals: { contract: contract }
    )

    # For draft contracts, also broadcast form and extraction status updates
    if contract.draft?
      Turbo::StreamsChannel.broadcast_replace_to(
        "contract_#{contract.id}",
        target: "draft_extraction_status",
        partial: "contracts/draft_extraction_status",
        locals: { contract: contract }
      )

      Turbo::StreamsChannel.broadcast_replace_to(
        "contract_#{contract.id}",
        target: "draft_contract_form",
        partial: "contracts/form",
        locals: { contract: contract, show_upload: false, draft_mode: true }
      )
    end
  end
end
