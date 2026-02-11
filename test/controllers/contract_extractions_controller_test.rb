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
end
