require "test_helper"

class ContractDraftCreatorServiceTest < ActiveSupport::TestCase
  include ActionDispatch::TestProcess::FixtureFile

  test "creates draft contract with documents" do
    file = fixture_file_upload("test.txt", "text/plain")

    contract = ContractDraftCreatorService.new(
      user: users(:one),
      organization: organizations(:one),
      files: [ file ],
      contract_type: "maintenance"
    ).call

    assert_equal "draft", contract.status
    assert_equal "Untitled Draft", contract.title
    assert_equal "maintenance", contract.contract_type
    assert_equal 1, contract.contract_documents.count
  end

  test "allows nil contract_type for unsure selection" do
    file = fixture_file_upload("test.txt", "text/plain")

    contract = ContractDraftCreatorService.new(
      user: users(:one),
      organization: organizations(:one),
      files: [ file ],
      contract_type: nil
    ).call

    assert_nil contract.contract_type
  end

  test "raises on invalid contract_type" do
    file = fixture_file_upload("test.txt", "text/plain")

    assert_raises ArgumentError do
      ContractDraftCreatorService.new(
        user: users(:one),
        organization: organizations(:one),
        files: [ file ],
        contract_type: "invalid_type"
      ).call
    end
  end
end
