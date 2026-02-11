require "test_helper"

class ContractTextExtractorServiceTest < ActiveSupport::TestCase
  setup do
    @contract = contracts(:hvac_maintenance)
  end

  # --- Plain text extraction ---

  test "extracts text from plain text file" do
    doc = create_document("This is a plain text contract.", "contract.txt", "text/plain")

    result = ContractTextExtractorService.new(doc).call

    assert_equal "This is a plain text contract.", result
    doc.reload
    assert_equal "completed", doc.extraction_status
    assert_equal "This is a plain text contract.", doc.extracted_text
    assert_nil doc.page_count
  end

  test "handles UTF-8 with invalid byte sequences in text files" do
    bad_bytes = "Valid text \xFF\xFE more text".dup
    bad_bytes.force_encoding("ASCII-8BIT")
    doc = create_document(bad_bytes, "messy.txt", "text/plain")

    result = ContractTextExtractorService.new(doc).call

    assert result.valid_encoding?, "Result should have valid UTF-8 encoding"
    assert_includes result, "Valid text"
    assert_includes result, "more text"
    doc.reload
    assert_equal "completed", doc.extraction_status
  end

  test "handles empty text file" do
    doc = create_document("", "empty.txt", "text/plain")

    result = ContractTextExtractorService.new(doc).call

    assert_equal "", result
    doc.reload
    assert_equal "completed", doc.extraction_status
  end

  # --- Status transitions ---

  test "sets status to processing then completed" do
    doc = create_document("Contract content", "contract.txt", "text/plain")

    ContractTextExtractorService.new(doc).call

    doc.reload
    assert_equal "completed", doc.extraction_status
  end

  test "sets status to failed on unsupported format error" do
    doc = create_document_bypassing_validation("content", "contract.xyz", "application/octet-stream")

    assert_raises(ContractTextExtractorService::UnsupportedFormatError) do
      ContractTextExtractorService.new(doc).call
    end

    doc.reload
    assert_equal "failed", doc.extraction_status
  end

  # --- Content type edge cases ---

  test "raises UnsupportedFormatError for blank content type" do
    doc = create_document("content", "noext", "text/plain")
    # Simulate blank content_type
    doc.define_singleton_method(:content_type) { nil }

    assert_raises(ContractTextExtractorService::UnsupportedFormatError) do
      ContractTextExtractorService.new(doc).call
    end
  end

  test "raises ExtractionError when no file is attached" do
    doc = @contract.contract_documents.new(
      extraction_status: "pending",
      document_type: "main_contract",
      position: 0
    )
    # Use insert_all to bypass validations and create a record without a file
    ContractDocument.insert_all([ {
      id: SecureRandom.uuid,
      contract_id: @contract.id,
      extraction_status: "pending",
      document_type: "main_contract",
      position: 99
    } ])
    doc = ContractDocument.find_by(position: 99, contract_id: @contract.id)

    assert_raises(ContractTextExtractorService::ExtractionError) do
      ContractTextExtractorService.new(doc).call
    end
  end

  test "raises UnsupportedFormatError for image content type" do
    doc = create_document_bypassing_validation("not an image", "photo.jpg", "image/jpeg")

    assert_raises(ContractTextExtractorService::UnsupportedFormatError) do
      ContractTextExtractorService.new(doc).call
    end

    doc.reload
    assert_equal "failed", doc.extraction_status
  end

  # --- PDF extraction ---

  test "extracts text from PDF file" do
    pdf_path = Rails.root.join("test/fixtures/files/sample.pdf")
    skip "No sample PDF fixture" unless File.exist?(pdf_path)

    doc = @contract.contract_documents.new(
      extraction_status: "pending",
      document_type: "main_contract",
      position: 0
    )
    doc.file.attach(io: File.open(pdf_path), filename: "sample.pdf", content_type: "application/pdf")
    doc.save!

    result = ContractTextExtractorService.new(doc).call

    assert result.present?
    doc.reload
    assert_equal "completed", doc.extraction_status
    assert doc.page_count.present?
    assert doc.page_count >= 1
  end

  test "raises ExtractionError for corrupt PDF" do
    doc = create_document("this is not a valid pdf", "corrupt.pdf", "application/pdf")

    error = assert_raises(ContractTextExtractorService::ExtractionError) do
      ContractTextExtractorService.new(doc).call
    end

    assert_match(/Could not read PDF/, error.message)
    doc.reload
    assert_equal "failed", doc.extraction_status
  end

  # --- DOCX extraction ---

  test "extracts text from DOCX file" do
    docx_path = Rails.root.join("test/fixtures/files/sample.docx")
    skip "No sample DOCX fixture" unless File.exist?(docx_path)

    doc = @contract.contract_documents.new(
      extraction_status: "pending",
      document_type: "main_contract",
      position: 0
    )
    doc.file.attach(io: File.open(docx_path), filename: "sample.docx",
                    content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
    doc.save!

    result = ContractTextExtractorService.new(doc).call

    assert result.present?
    assert_includes result, "Acme Corp"
    assert_includes result, "Test Vendor"
    doc.reload
    assert_equal "completed", doc.extraction_status
    assert_nil doc.page_count
  end

  test "extracts table content from DOCX file" do
    docx_path = Rails.root.join("test/fixtures/files/sample_with_tables.docx")
    skip "No sample_with_tables DOCX fixture" unless File.exist?(docx_path)

    doc = @contract.contract_documents.new(
      extraction_status: "pending",
      document_type: "main_contract",
      position: 0
    )
    doc.file.attach(io: File.open(docx_path), filename: "sample_with_tables.docx",
                    content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
    doc.save!

    result = ContractTextExtractorService.new(doc).call

    assert result.present?
    # Paragraph content
    assert_includes result, "Acme Corp"
    assert_includes result, "Test Vendor"
    # Table content — these were previously invisible to the extractor
    assert_includes result, "[Table]"
    assert_includes result, "Start Date"
    assert_includes result, "March 15, 2025"
    assert_includes result, "End Date"
    assert_includes result, "March 14, 2026"
    assert_includes result, "$2,500.00"
    assert_includes result, "60 days"
    doc.reload
    assert_equal "completed", doc.extraction_status
    assert_nil doc.page_count
  end

  test "raises ExtractionError for corrupt DOCX" do
    doc = create_document("this is not a valid docx", "corrupt.docx",
                          "application/vnd.openxmlformats-officedocument.wordprocessingml.document")

    error = assert_raises(ContractTextExtractorService::ExtractionError) do
      ContractTextExtractorService.new(doc).call
    end

    assert_match(/Could not read DOCX/, error.message)
    doc.reload
    assert_equal "failed", doc.extraction_status
  end

  # --- Text truncation ---

  test "truncates excessively large extracted text" do
    max_len = ContractTextExtractorService::MAX_EXTRACTED_TEXT_LENGTH
    large_text = "A" * (max_len + 1000)
    doc = create_document(large_text, "huge.txt", "text/plain")

    result = ContractTextExtractorService.new(doc).call

    assert result.length <= max_len + 100, "Result should be truncated near MAX_EXTRACTED_TEXT_LENGTH"
    assert_includes result, "[Text truncated"
    doc.reload
    assert_equal "completed", doc.extraction_status
  end

  test "does not truncate text within size limit" do
    normal_text = "B" * 1000
    doc = create_document(normal_text, "normal.txt", "text/plain")

    result = ContractTextExtractorService.new(doc).call

    assert_equal normal_text, result
    refute_includes result, "[Text truncated"
  end

  private

  def create_document(content, filename, content_type)
    doc = @contract.contract_documents.new(
      extraction_status: "pending",
      document_type: "main_contract",
      position: @contract.contract_documents.count
    )
    doc.file.attach(
      io: StringIO.new(content),
      filename: filename,
      content_type: content_type
    )
    doc.save!
    doc
  end

  # Creates a document with a content type that would normally be rejected by
  # model validation. Used to test the service's own error handling for
  # unsupported formats that might arrive via background job re-processing.
  def create_document_bypassing_validation(content, filename, content_type)
    doc = @contract.contract_documents.new(
      extraction_status: "pending",
      document_type: "main_contract",
      position: @contract.contract_documents.count
    )
    doc.file.attach(
      io: StringIO.new(content),
      filename: filename,
      content_type: content_type
    )
    doc.save(validate: false)
    doc
  end
end
