require "test_helper"

class ContractDocumentTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @contract = contracts(:hvac_maintenance)
  end

  test "valid contract document with file" do
    doc = @contract.contract_documents.new(extraction_status: "pending", document_type: "main_contract", position: 0)
    doc.file.attach(
      io: StringIO.new("Sample contract text content"),
      filename: "contract.txt",
      content_type: "text/plain"
    )
    assert doc.valid?
  end

  test "requires file attachment" do
    doc = @contract.contract_documents.new(extraction_status: "pending", document_type: "main_contract", position: 0)
    assert_not doc.valid?
    assert_includes doc.errors[:file], "can't be blank"
  end

  test "validates extraction_status inclusion" do
    doc = contract_documents(:completed_doc)
    doc.file.attach(
      io: StringIO.new("text"),
      filename: "test.txt",
      content_type: "text/plain"
    )
    doc.extraction_status = "invalid"
    assert_not doc.valid?
  end

  test "belongs to contract" do
    doc = contract_documents(:completed_doc)
    assert_equal @contract, doc.contract
  end

  test "completed scope" do
    completed = ContractDocument.completed
    assert_includes completed, contract_documents(:completed_doc)
    assert_not_includes completed, contract_documents(:pending_doc)
  end

  test "pending scope" do
    pending_docs = ContractDocument.pending
    assert_includes pending_docs, contract_documents(:pending_doc)
    assert_not_includes pending_docs, contract_documents(:completed_doc)
  end

  test "filename returns file name" do
    doc = @contract.contract_documents.new(document_type: "main_contract", position: 0)
    doc.file.attach(
      io: StringIO.new("text"),
      filename: "my_contract.pdf",
      content_type: "application/pdf"
    )
    assert_equal "my_contract.pdf", doc.filename
  end

  test "pdf? returns true for PDF files" do
    doc = @contract.contract_documents.new(document_type: "main_contract", position: 0)
    doc.file.attach(
      io: StringIO.new("text"),
      filename: "contract.pdf",
      content_type: "application/pdf"
    )
    assert doc.pdf?
    assert_not doc.docx?
  end

  test "docx? returns true for DOCX files" do
    doc = @contract.contract_documents.new(document_type: "main_contract", position: 0)
    doc.file.attach(
      io: StringIO.new("text"),
      filename: "contract.docx",
      content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    )
    assert doc.docx?
    assert_not doc.pdf?
  end

  test "status helper methods" do
    doc = contract_documents(:pending_doc)
    assert doc.pending?
    assert_not doc.completed?
    assert_not doc.processing?
    assert_not doc.failed?

    completed = contract_documents(:completed_doc)
    assert completed.completed?
    assert_not completed.pending?
  end

  test "file_size_human formats bytes" do
    doc = @contract.contract_documents.new(document_type: "main_contract", position: 0)
    doc.file.attach(
      io: StringIO.new("x" * 2048),
      filename: "test.txt",
      content_type: "text/plain"
    )
    assert_match(/KB/, doc.file_size_human)
  end

  test "extraction_status_label" do
    doc = contract_documents(:pending_doc)
    assert_equal "Pending", doc.extraction_status_label

    completed = contract_documents(:completed_doc)
    assert_equal "Completed", completed.extraction_status_label
  end

  test "enqueues extraction job on create" do
    doc = @contract.contract_documents.new(extraction_status: "pending", document_type: "main_contract", position: 0)
    doc.file.attach(
      io: StringIO.new("Sample text"),
      filename: "contract.txt",
      content_type: "text/plain"
    )

    assert_enqueued_with(job: ExtractContractDocumentJob) do
      doc.save!
    end
  end

  test "destroying document removes it from contract" do
    doc = @contract.contract_documents.new(extraction_status: "completed", document_type: "main_contract", position: 0)
    doc.file.attach(
      io: StringIO.new("text"),
      filename: "test.txt",
      content_type: "text/plain"
    )
    doc.save!

    assert_difference "@contract.contract_documents.count", -1 do
      doc.destroy!
    end
  end

  test "validates document_type inclusion" do
    doc = @contract.contract_documents.new(extraction_status: "pending", document_type: "invalid_type", position: 0)
    doc.file.attach(
      io: StringIO.new("text"),
      filename: "test.txt",
      content_type: "text/plain"
    )
    assert_not doc.valid?
    assert_includes doc.errors[:document_type], "is not included in the list"
  end

  test "document_type_label returns titleized label" do
    doc = contract_documents(:completed_doc)
    assert_equal "Main Contract", doc.document_type_label
  end

  test "ordered scope sorts by position then created_at" do
    docs = @contract.contract_documents.ordered
    positions = docs.pluck(:position)
    assert_equal positions, positions.sort
  end

  test "DOCUMENT_TYPES constant includes expected types" do
    assert_includes ContractDocument::DOCUMENT_TYPES, "main_contract"
    assert_includes ContractDocument::DOCUMENT_TYPES, "addendum"
    assert_includes ContractDocument::DOCUMENT_TYPES, "amendment"
    assert_includes ContractDocument::DOCUMENT_TYPES, "exhibit"
    assert_includes ContractDocument::DOCUMENT_TYPES, "sow"
    assert_includes ContractDocument::DOCUMENT_TYPES, "other"
  end

  test "has_many key_clauses via source_document_id" do
    doc = contract_documents(:completed_doc)
    assert_respond_to doc, :key_clauses
  end

  # --- Server-side content type validation ---

  test "rejects disallowed content types" do
    doc = @contract.contract_documents.new(extraction_status: "pending", document_type: "main_contract", position: 0)
    doc.file.attach(
      io: StringIO.new("fake image data"),
      filename: "photo.jpg",
      content_type: "image/jpeg"
    )
    assert_not doc.valid?
    assert doc.errors[:file].any? { |e| e.include?("must be a PDF") }
  end

  test "accepts PDF content type" do
    doc = @contract.contract_documents.new(extraction_status: "pending", document_type: "main_contract", position: 0)
    doc.file.attach(
      io: StringIO.new("pdf data"),
      filename: "contract.pdf",
      content_type: "application/pdf"
    )
    assert doc.valid?
  end

  test "accepts DOCX content type" do
    doc = @contract.contract_documents.new(extraction_status: "pending", document_type: "main_contract", position: 0)
    doc.file.attach(
      io: StringIO.new("docx data"),
      filename: "contract.docx",
      content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    )
    assert doc.valid?
  end

  test "accepts text/plain content type" do
    doc = @contract.contract_documents.new(extraction_status: "pending", document_type: "main_contract", position: 0)
    doc.file.attach(
      io: StringIO.new("text data"),
      filename: "contract.txt",
      content_type: "text/plain"
    )
    assert doc.valid?
  end

  test "rejects application/octet-stream content type" do
    doc = @contract.contract_documents.new(extraction_status: "pending", document_type: "main_contract", position: 0)
    doc.file.attach(
      io: StringIO.new("binary data"),
      filename: "unknown.bin",
      content_type: "application/octet-stream"
    )
    assert_not doc.valid?
    assert doc.errors[:file].any? { |e| e.include?("must be a PDF") }
  end

  # --- Server-side file size validation ---

  test "rejects files exceeding max size" do
    doc = @contract.contract_documents.new(extraction_status: "pending", document_type: "main_contract", position: 0)
    # Create content larger than MAX_FILE_SIZE
    large_content = "x" * (ContractDocument::MAX_FILE_SIZE + 1)
    doc.file.attach(
      io: StringIO.new(large_content),
      filename: "huge.txt",
      content_type: "text/plain"
    )
    assert_not doc.valid?
    assert doc.errors[:file].any? { |e| e.include?("too large") }
  end

  test "accepts files within max size" do
    doc = @contract.contract_documents.new(extraction_status: "pending", document_type: "main_contract", position: 0)
    doc.file.attach(
      io: StringIO.new("small file content"),
      filename: "small.txt",
      content_type: "text/plain"
    )
    assert doc.valid?
  end

  # --- Callback: after_destroy cleanup ---

  test "after_destroy triggers re-extraction when completed docs remain" do
    @contract.contract_documents.update_all(extraction_status: "completed")

    doc_to_delete = @contract.contract_documents.new(extraction_status: "completed", document_type: "addendum", position: 1)
    doc_to_delete.file.attach(io: StringIO.new("text"), filename: "delete.txt", content_type: "text/plain")
    doc_to_delete.save!

    assert_enqueued_with(job: AiExtractContractJob) do
      doc_to_delete.destroy!
    end

    @contract.reload
    assert_equal "pending", @contract.extraction_status
  end

  test "after_destroy clears AI data when no documents remain" do
    # Remove all existing docs first
    @contract.contract_documents.destroy_all
    @contract.update!(ai_extracted_data: '{"vendor": "test"}', extraction_status: "completed")

    doc = @contract.contract_documents.new(extraction_status: "completed", document_type: "main_contract", position: 0)
    doc.file.attach(io: StringIO.new("text"), filename: "last.txt", content_type: "text/plain")
    doc.save!

    doc.destroy!

    @contract.reload
    assert_nil @contract.ai_extracted_data
    assert_equal "pending", @contract.extraction_status
  end

  # --- Constants ---

  test "MAX_FILE_SIZE is defined and reasonable" do
    assert ContractDocument::MAX_FILE_SIZE > 0
    assert ContractDocument::MAX_FILE_SIZE <= 100.megabytes
  end

  test "ALLOWED_CONTENT_TYPES includes expected types" do
    assert_includes ContractDocument::ALLOWED_CONTENT_TYPES, "application/pdf"
    assert_includes ContractDocument::ALLOWED_CONTENT_TYPES, "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    assert_includes ContractDocument::ALLOWED_CONTENT_TYPES, "text/plain"
    assert_equal 3, ContractDocument::ALLOWED_CONTENT_TYPES.length
  end
end
