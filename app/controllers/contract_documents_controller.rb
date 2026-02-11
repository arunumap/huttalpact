class ContractDocumentsController < ApplicationController
  before_action :set_contract

  def create
    @contract_document = @contract.contract_documents.new(
      document_type: params[:document_type].presence || "main_contract"
    )
    @contract_document.file.attach(params[:file])

    # Assign position inside save transaction to reduce race window on concurrent uploads
    @contract_document.position = @contract.contract_documents.maximum(:position).to_i + 1

    if @contract_document.save
      log_audit("updated", contract: @contract, details: "Uploaded document: #{@contract_document.file.filename}")
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.append(
            "contract_documents",
            partial: "contract_documents/contract_document",
            locals: { contract_document: @contract_document }
          ) + turbo_stream.update("document_upload_flash", partial: "contract_documents/upload_flash", locals: { message: "#{@contract_document.filename} uploaded successfully. Extracting text...", type: "success" }) + turbo_stream.update("empty_documents_state", "")
        end
        format.html { redirect_to @contract, notice: "Document uploaded successfully." }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update(
            "document_upload_flash",
            partial: "contract_documents/upload_flash",
            locals: { message: "Failed to upload document. #{@contract_document.errors.full_messages.join(', ')}", type: "error" }
          )
        end
        format.html { redirect_to @contract, alert: "Failed to upload document." }
      end
    end
  end

  def destroy
    @contract_document = @contract.contract_documents.find(params[:id])

    # Prevent deletion while any extraction is in progress
    if @contract.contract_documents.where(extraction_status: %w[pending processing]).exists? ||
       @contract.extraction_status == "processing"
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update(
            "document_upload_flash",
            partial: "contract_documents/upload_flash",
            locals: { message: "Cannot delete documents while extraction is in progress.", type: "error" }
          )
        end
        format.html { redirect_to @contract, alert: "Cannot delete documents while extraction is in progress." }
      end
      return
    end

    @contract_document.destroy!
    log_audit("updated", contract: @contract, details: "Deleted document: #{@contract_document.file.filename}")

    respond_to do |format|
      format.turbo_stream do
        streams = turbo_stream.remove("contract_document_#{@contract_document.id}")
        if @contract.contract_documents.reload.empty?
          streams += turbo_stream.update("empty_documents_state", partial: "contract_documents/empty_state")
        end
        render turbo_stream: streams
      end
      format.html { redirect_to @contract, notice: "Document deleted." }
    end
  end

  private

  def set_contract
    @contract = Contract.find(params[:contract_id])
  end
end
