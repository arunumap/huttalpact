require "test_helper"

class ContractExtractionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @contract = contracts(:hvac_maintenance)
  end

  test "should start extraction when completed documents exist" do
    assert @contract.contract_documents.completed.any?, "Expected completed documents for test"

    assert_enqueued_with(job: AiExtractContractJob, args: [ @contract.id ]) do
      post contract_extraction_path(@contract)
    end

    assert_redirected_to contract_path(@contract)
    assert_match "AI extraction started", flash[:notice]

    @contract.reload
    assert_equal "pending", @contract.extraction_status
  end

  test "turbo stream request shows analyzing state immediately" do
    @contract.update!(extraction_status: "completed", ai_extracted_data: '{"vendor_name":"Acme"}')

    assert_enqueued_with(job: AiExtractContractJob, args: [ @contract.id ]) do
      post contract_extraction_path(@contract), as: :turbo_stream
    end

    assert_response :success
    assert_equal Mime[:turbo_stream].to_s, response.media_type
    assert_includes response.body, 'target="contract_ai_status"'
    assert_includes response.body, "AI is analyzing your contract..."
    assert_not_includes response.body, "Ready for AI extraction"

    @contract.reload
    assert_equal "pending", @contract.extraction_status
  end

  test "should redirect with alert when no completed documents" do
    @contract.contract_documents.update_all(extraction_status: "pending")

    post contract_extraction_path(@contract)

    assert_redirected_to contract_path(@contract)
    assert_match "No extracted documents", flash[:alert]
  end

  test "should not eagerly destroy key clauses on re-extract" do
    initial_count = @contract.key_clauses.count
    assert initial_count > 0, "Expected key clauses from fixtures"

    # Clauses are now destroyed atomically inside the service, not in the controller
    assert_no_difference "KeyClause.count" do
      assert_enqueued_with(job: AiExtractContractJob) do
        post contract_extraction_path(@contract)
      end
    end
  end

  test "redirects to login when not authenticated" do
    sign_out
    post contract_extraction_path(@contract)
    assert_redirected_to new_session_path
  end

  test "extraction blocked when at extraction limit" do
    org = organizations(:one)
    org.update!(plan: "free", ai_extractions_count: 5, ai_extractions_reset_at: Time.current)

    post contract_extraction_path(@contract)
    assert_redirected_to contract_path(@contract)
    assert_match "extractions", flash[:alert]
  end

  test "create redirects to edit when contract type is blank" do
    @contract.update!(contract_type: nil)

    post contract_extraction_path(@contract)

    assert_redirected_to edit_contract_path(@contract)
    assert_match "choose a contract type", flash[:alert]
  end

  test "confirm_type sets type and starts extraction" do
    @contract.update!(contract_type: nil, extraction_status: "awaiting_type_confirmation")

    assert_enqueued_with(job: AiExtractContractJob, args: [ @contract.id ]) do
      post confirm_type_contract_extraction_path(@contract), params: { contract_type: "lease" }
    end

    @contract.reload
    assert_equal "lease", @contract.contract_type
    assert_equal "pending", @contract.extraction_status
    assert_redirected_to contract_path(@contract)
  end

  test "confirm_type rejects invalid type" do
    @contract.update!(contract_type: nil, extraction_status: "awaiting_type_confirmation")

    assert_no_enqueued_jobs do
      post confirm_type_contract_extraction_path(@contract), params: { contract_type: "not-a-type" }
    end

    @contract.reload
    assert_nil @contract.contract_type
    assert_equal "awaiting_type_confirmation", @contract.extraction_status
    assert_redirected_to edit_contract_path(@contract)
    assert_match "valid contract type", flash[:alert]
  end

  test "redetect now redirects user to explicit type selection" do
    post redetect_contract_extraction_path(@contract)

    assert_redirected_to edit_contract_path(@contract)
    assert_match "Auto-detect has been retired", flash[:alert]
  end
end
