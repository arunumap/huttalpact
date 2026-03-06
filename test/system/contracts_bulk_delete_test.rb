require "application_system_test_case"

class ContractsBulkDeleteTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
    @contract = contracts(:hvac_maintenance)
    @contract_two = contracts(:landscaping)
    sign_in_as(@user)
  end

  test "marks selected rows queued and removes them as bulk delete finishes" do
    visit contracts_path

    find("input[data-bulk-select-target='checkbox'][value='#{@contract.id}']", visible: :visible).check
    find("input[data-bulk-select-target='checkbox'][value='#{@contract_two.id}']", visible: :visible).check

    accept_confirm do
      click_button "Delete"
    end

    assert_text "Queued for deletion", count: 2
    assert_text "Deleting 2 contracts in background", wait: 5

    perform_enqueued_jobs only: BulkDeleteContractsJob

    assert_no_text @contract.title, wait: 5
    assert_no_text @contract_two.title, wait: 5
    assert_text "Deleted 2 contracts", wait: 5
  end
end
