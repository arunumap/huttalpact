require "test_helper"

class ContractDraftCreatorServiceTest < ActiveSupport::TestCase
  include ActionDispatch::TestProcess::FixtureFile

  test "creates draft contract with documents" do
    file = fixture_file_upload("test.txt", "text/plain")

    contract = ContractDraftCreatorService.new(
      user: users(:one),
      organization: organizations(:one),
      files: [ file ]
    ).call

    assert_equal "draft", contract.status
    assert_equal "Untitled Draft", contract.title
    assert_equal 1, contract.contract_documents.count
  end
end
