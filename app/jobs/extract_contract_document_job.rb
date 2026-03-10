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
            if org.at_extraction_limit? && !org.extraction_overage_enabled?
              Rails.logger.info("Skipping auto AI extraction for contract #{contract.id}: org #{org.id} at extraction limit (#{org.ai_extractions_count}/#{org.plan_extraction_limit})")
              next
            end
          end

          unless contract_type_ready_for_extraction?(contract)
            broadcast_type_confirmation_needed(contract)
            next
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

    # Broadcast progress update to review processing page (if user is already there)
    contract = document.contract
    if contract.draft?
      Turbo::StreamsChannel.broadcast_replace_to(
        "contract_#{contract.id}",
        target: "review_extraction_processing",
        partial: "contract_reviews/extraction_status",
        locals: { contract: contract }
      )
    end
  end

  def contract_type_ready_for_extraction?(contract)
    return false if contract.extraction_status == "awaiting_type_confirmation"
    return true if contract.contract_type.present?

    classification = ContractTypeClassifierService.new(contract).call

    if classification.confident?
      detected_type = classification.suggested_type
      contract.update!(
        contract_type: detected_type,
        extraction_status: "pending",
        last_changes_summary: "Auto-detected contract type as #{human_contract_type_label(detected_type)} (#{classification.confidence}% confidence)."
      )

      AuditLog.create(
        organization: contract.organization,
        contract: contract,
        action: "updated",
        details: "Auto-detected contract type as #{detected_type} after user selected unsure."
      )
      true
    else
      contract.update!(
        extraction_status: "awaiting_type_confirmation",
        last_changes_summary: awaiting_type_confirmation_message(classification)
      )

      AuditLog.create(
        organization: contract.organization,
        contract: contract,
        action: "updated",
        details: "Paused extraction pending contract type confirmation."
      )
      false
    end
  end

  def awaiting_type_confirmation_message(classification)
    return "We couldn't confidently determine the contract type. Please choose a type to continue extraction." if classification.suggested_type.blank?

    "We need your confirmation before extracting. Best guess: #{human_contract_type_label(classification.suggested_type)} (#{classification.confidence}% confidence)."
  end

  def human_contract_type_label(type)
    return "MSA / Service Agreement" if type == "service_agreement"

    type.to_s.titleize.gsub("_", " ")
  end

  def broadcast_type_confirmation_needed(contract)
    if contract.draft?
      Turbo::StreamsChannel.broadcast_replace_to(
        "contract_#{contract.id}",
        target: "draft_extraction_status",
        partial: "contracts/draft_extraction_status",
        locals: { contract: contract }
      )

      # Broadcast to review processing page (if user is already there)
      Turbo::StreamsChannel.broadcast_replace_to(
        "contract_#{contract.id}",
        target: "review_extraction_processing",
        partial: "contract_reviews/extraction_status",
        locals: { contract: contract }
      )
    end

    Turbo::StreamsChannel.broadcast_replace_to(
      "contract_#{contract.id}",
      target: "contract_ai_status",
      partial: "contracts/ai_status",
      locals: { contract: contract }
    )
  end
end
