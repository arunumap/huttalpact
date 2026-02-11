require "test_helper"

class ContractDocumentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @contract = contracts(:hvac_maintenance)
  end

  # --- Upload tests (HTML) ---

  test "should upload a document via HTML" do
    file = fixture_file_upload("test.txt", "text/plain")

    assert_difference "@contract.contract_documents.count", 1 do
      post contract_documents_path(@contract), params: { file: file }
    end

    assert_redirected_to contract_path(@contract)
  end

  test "should upload a document via turbo_stream" do
    file = fixture_file_upload("test.txt", "text/plain")

    assert_difference "@contract.contract_documents.count", 1 do
      post contract_documents_path(@contract),
           params: { file: file },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_match "turbo-stream", response.body
  end

  # --- Server-side content type validation ---

  test "rejects upload with disallowed content type" do
    file = fixture_file_upload("test.txt", "image/png")

    assert_no_difference "@contract.contract_documents.count" do
      post contract_documents_path(@contract), params: { file: file }
    end
  end

  test "rejects disallowed content type via turbo_stream with error message" do
    file = fixture_file_upload("test.txt", "image/jpeg")

    assert_no_difference "@contract.contract_documents.count" do
      post contract_documents_path(@contract),
           params: { file: file },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_match "turbo-stream", response.body
    assert_match(/Failed to upload|must be a PDF/, response.body)
  end

  # --- Document deletion ---

  test "should destroy a document" do
    @contract.contract_documents.update_all(extraction_status: "completed")

    doc = create_completed_doc("delete_me.txt")

    assert_difference "@contract.contract_documents.count", -1 do
      delete contract_document_path(@contract, doc)
    end

    assert_redirected_to contract_path(@contract)
  end

  test "should destroy a document via turbo_stream" do
    @contract.contract_documents.update_all(extraction_status: "completed")

    doc = create_completed_doc("delete_me.txt")

    assert_difference "@contract.contract_documents.count", -1 do
      delete contract_document_path(@contract, doc),
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_match "turbo-stream", response.body
  end

  # --- Deletion guards ---

  test "should block deletion while extraction in progress" do
    doc = @contract.contract_documents.new(extraction_status: "processing", document_type: "main_contract", position: 0)
    doc.file.attach(
      io: StringIO.new("text"),
      filename: "processing_doc.txt",
      content_type: "text/plain"
    )
    doc.save!

    assert_no_difference "@contract.contract_documents.count" do
      delete contract_document_path(@contract, doc)
    end

    assert_redirected_to contract_path(@contract)
    assert_match "Cannot delete", flash[:alert]
  end

  test "should block deletion while AI extraction is processing" do
    @contract.contract_documents.update_all(extraction_status: "completed")
    @contract.update_column(:extraction_status, "processing")

    doc = create_completed_doc("blocked_by_ai.txt")

    assert_no_difference "@contract.contract_documents.count" do
      delete contract_document_path(@contract, doc)
    end

    assert_redirected_to contract_path(@contract)
    assert_match "Cannot delete", flash[:alert]
  end

  test "should block deletion via turbo_stream while extraction in progress" do
    doc = @contract.contract_documents.new(extraction_status: "pending", document_type: "main_contract", position: 0)
    doc.file.attach(io: StringIO.new("text"), filename: "pending.txt", content_type: "text/plain")
    doc.save!

    assert_no_difference "@contract.contract_documents.count" do
      delete contract_document_path(@contract, doc),
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_match "Cannot delete", response.body
  end

  # --- Job enqueuing ---

  test "enqueues extraction job after upload" do
    file = fixture_file_upload("test.txt", "text/plain")

    assert_enqueued_with(job: ExtractContractDocumentJob) do
      post contract_documents_path(@contract), params: { file: file }
    end
  end

  # --- Document type handling ---

  test "should accept document_type param on upload" do
    file = fixture_file_upload("test.txt", "text/plain")

    post contract_documents_path(@contract),
         params: { file: file, document_type: "addendum" }

    assert_redirected_to contract_path(@contract)
    doc = @contract.contract_documents.order(created_at: :desc).first
    assert_equal "addendum", doc.document_type
  end

  test "defaults document_type to main_contract" do
    file = fixture_file_upload("test.txt", "text/plain")

    post contract_documents_path(@contract), params: { file: file }

    doc = @contract.contract_documents.order(created_at: :desc).first
    assert_equal "main_contract", doc.document_type
  end

  # --- Position auto-increment ---

  test "auto-increments position on upload" do
    file1 = fixture_file_upload("test.txt", "text/plain")
    post contract_documents_path(@contract), params: { file: file1 }

    file2 = fixture_file_upload("test.txt", "text/plain")
    post contract_documents_path(@contract), params: { file: file2 }

    docs = @contract.contract_documents.order(created_at: :desc).limit(2)
    positions = docs.pluck(:position)
    assert positions.uniq.length == 2, "Expected unique positions"
  end

  # --- Display tests ---

  test "contract show page displays documents section" do
    get contract_path(@contract)
    assert_response :success
    assert_select "h3", "Documents"
  end

  test "contract show page displays uploaded documents" do
    doc = create_completed_doc("visible_doc.txt")

    get contract_path(@contract)
    assert_response :success
    assert_match "visible_doc.txt", response.body
  end

  # --- Authentication ---

  test "redirects to login when not authenticated" do
    sign_out
    file = fixture_file_upload("test.txt", "text/plain")
    post contract_documents_path(@contract), params: { file: file }
    assert_redirected_to new_session_path
  end

  # --- Audit log tests ---

  test "document upload creates audit log" do
    file = fixture_file_upload("test.txt", "text/plain")

    assert_difference "AuditLog.count" do
      post contract_documents_path(@contract), params: { file: file }
    end

    log = AuditLog.last
    assert_equal "updated", log.action
    assert_equal @contract.id, log.contract_id
    assert_match "Uploaded document", log.details
  end

  test "document deletion creates audit log" do
    @contract.contract_documents.update_all(extraction_status: "completed")

    doc = create_completed_doc("audit_test.txt")

    assert_difference "AuditLog.count" do
      delete contract_document_path(@contract, doc)
    end

    log = AuditLog.last
    assert_equal "updated", log.action
    assert_equal @contract.id, log.contract_id
    assert_match "Deleted document", log.details
  end

  # --- Upload without file ---

  test "rejects upload without file param" do
    assert_no_difference "@contract.contract_documents.count" do
      post contract_documents_path(@contract), params: {}
    end
  end

  private

  def create_completed_doc(filename)
    doc = @contract.contract_documents.new(
      extraction_status: "completed",
      document_type: "main_contract",
      position: @contract.contract_documents.maximum(:position).to_i + 1
    )
    doc.file.attach(
      io: StringIO.new("text content"),
      filename: filename,
      content_type: "text/plain"
    )
    doc.save!
    doc
  end
end
