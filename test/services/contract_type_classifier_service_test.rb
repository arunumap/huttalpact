require "test_helper"

class ContractTypeClassifierServiceTest < ActiveSupport::TestCase
  include ActionDispatch::TestProcess::FixtureFile

  test "classifies msa text as service_agreement with high confidence" do
    contract = contracts(:hvac_maintenance)
    contract.contract_documents.destroy_all
    create_completed_document(contract, <<~TEXT)
      MASTER SERVICE AGREEMENT
      This MSA defines the scope of services, deliverables, and service levels.
      Individual Statements of Work (SOW) may be added from time to time.
    TEXT

    result = ContractTypeClassifierService.new(contract).call

    assert_equal "service_agreement", result.suggested_type
    assert result.confident?
    assert_operator result.confidence, :>=, 70
  end

  test "returns low confidence for ambiguous text" do
    contract = contracts(:hvac_maintenance)
    contract.contract_documents.destroy_all
    create_completed_document(contract, "General agreement terms and obligations between parties.")

    result = ContractTypeClassifierService.new(contract).call

    refute result.confident?
    assert_operator result.confidence, :<=, 69
  end

  private

  def create_completed_document(contract, text)
    contract.contract_documents.create!(
      extraction_status: "completed",
      extracted_text: text,
      document_type: "main_contract",
      position: 0,
      file: fixture_file_upload("test.txt", "text/plain")
    )
  end
end
