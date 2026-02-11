class ExtractContractDocumentJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ContractTextExtractorService::UnsupportedFormatError

  def perform(contract_document_id)
    document = ContractDocument.find(contract_document_id)

    # Idempotency guard: skip if already completed (e.g., job retried after success)
    if document.completed?
      Rails.logger.info("Document #{contract_document_id} already extracted, skipping text extraction")
    else
      ContractTextExtractorService.new(document).call
      document.reload
    end

    # Broadcast the updated document to the contract show page
    broadcast_update(document)

    # Chain AI extraction only when ALL documents have finished text extraction
    # Use with_lock to prevent race condition when multiple docs finish simultaneously
    if document.completed?
      contract = document.contract
      contract.with_lock do
        all_done = contract.contract_documents.where.not(
          extraction_status: %w[completed failed]
        ).none?

        if all_done
          # Check extraction limit before enqueuing AI job
          org = contract.organization
          if org
            org.reset_monthly_extractions_if_needed!
            if org.at_extraction_limit?
              Rails.logger.info("Skipping auto AI extraction for contract #{contract.id}: org #{org.id} at extraction limit (#{org.ai_extractions_count}/#{org.plan_extraction_limit})")
              next
            end
          end

          # If the contract already has AI data and this is a new document,
          # use incremental mode so user edits are preserved
          if contract.ai_extracted_data.present?
            AiExtractContractJob.perform_later(contract.id, new_document_id: document.id)
          else
            AiExtractContractJob.perform_later(contract.id)
          end
        end
      end
    end
  rescue ActiveRecord::RecordNotFound
    # Document was deleted before job ran — nothing to do
    Rails.logger.warn("ContractDocument #{contract_document_id} not found, skipping extraction")
  end

  private

  def broadcast_update(document)
    Turbo::StreamsChannel.broadcast_replace_to(
      "contract_#{document.contract_id}_documents",
      target: "contract_document_#{document.id}",
      partial: "contract_documents/contract_document",
      locals: { contract_document: document }
    )
  end
end
