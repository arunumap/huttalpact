require "test_helper"

class ContractsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @contract = contracts(:hvac_maintenance)
  end

  # Index
  test "should get index" do
    get contracts_path
    assert_response :success
    assert_select "table"
  end

  test "index shows contracts for current organization only" do
    get contracts_path
    assert_response :success
    # Should see org one's contracts
    assert_match @contract.title, response.body
    # Should NOT see org two's contracts
    assert_no_match(/Office Lease/, response.body)
  end

  test "index filters by status" do
    get contracts_path(status: "expired")
    assert_response :success
    assert_select "turbo-frame#contracts" do
      assert_select "a", text: "Property Insurance - Portfolio"
      assert_select "a", text: "HVAC Maintenance - Building A", count: 0
    end
  end

  test "index filters by contract_type" do
    get contracts_path(contract_type: "maintenance")
    assert_response :success
    assert_select "turbo-frame#contracts" do
      assert_select "a", text: "HVAC Maintenance - Building A"
      assert_select "a", text: "Landscaping Services", count: 0
    end
  end

  test "index searches by title" do
    get contracts_path(search: "HVAC")
    assert_response :success
    assert_select "turbo-frame#contracts" do
      assert_select "a", text: "HVAC Maintenance - Building A"
      assert_select "a", text: "Landscaping Services", count: 0
    end
  end

  test "index searches by vendor" do
    get contracts_path(search: "Green Thumb")
    assert_response :success
    assert_select "turbo-frame#contracts" do
      assert_select "a", text: "Landscaping Services"
      assert_select "a", text: "HVAC Maintenance - Building A", count: 0
    end
  end

  # Show
  test "should get show" do
    get contract_path(@contract)
    assert_response :success
    assert_match @contract.title, response.body
    assert_match @contract.vendor_name, response.body
  end

  # New
  test "should get new" do
    get new_contract_path
    assert_response :success
  end

  # Create
  test "should create contract" do
    assert_difference "Contract.count", 1 do
      post contracts_path, params: {
        contract: {
          title: "New Test Contract",
          vendor_name: "Test Vendor",
          contract_type: "software",
          status: "active",
          start_date: Date.current,
          end_date: 1.year.from_now.to_date,
          monthly_value: 99.99
        }
      }
    end

    contract = Contract.order(created_at: :desc).first
    assert_equal "New Test Contract", contract.title
    assert_equal users(:one), contract.uploaded_by
    assert_equal organizations(:one), contract.organization
    assert_redirected_to contract_path(contract)
  end

  test "should not create contract with invalid params" do
    assert_no_difference "Contract.count" do
      post contracts_path, params: {
        contract: { title: "" }
      }
    end
    assert_response :unprocessable_entity
  end

  # Edit
  test "should get edit" do
    get edit_contract_path(@contract)
    assert_response :success
  end

  # Update
  test "should update contract" do
    patch contract_path(@contract), params: {
      contract: { title: "Updated Title", vendor_name: "Updated Vendor" }
    }
    assert_redirected_to contract_path(@contract)
    @contract.reload
    assert_equal "Updated Title", @contract.title
    assert_equal "Updated Vendor", @contract.vendor_name
  end

  test "should not update contract with invalid params" do
    patch contract_path(@contract), params: {
      contract: { title: "" }
    }
    assert_response :unprocessable_entity
  end

  # Destroy
  test "should destroy contract" do
    assert_difference "Contract.count", -1 do
      delete contract_path(@contract)
    end
    assert_redirected_to contracts_path
  end

  # Auth
  test "redirects to login when not authenticated" do
    sign_out
    get contracts_path
    assert_redirected_to new_session_path
  end

  # CSV Export
  test "index exports CSV" do
    get contracts_path(format: :csv)
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match "Title,Vendor,Status", response.body
    assert_match @contract.title, response.body
  end

  test "CSV export respects filters" do
    get contracts_path(format: :csv, status: "active")
    assert_response :success
    assert_match @contract.title, response.body
    assert_no_match(/Landscaping/, response.body)
  end

  test "CSV export creates audit log" do
    assert_difference "AuditLog.count" do
      get contracts_path(format: :csv)
    end
    assert_equal "exported", AuditLog.last.action
  end

  # Bulk Actions
  test "bulk_archive archives selected contracts" do
    contract2 = contracts(:landscaping)
    post bulk_archive_contracts_path, params: { ids: [ @contract.id, contract2.id ] }
    assert_redirected_to contracts_path
    assert_equal "archived", @contract.reload.status
    assert_equal "archived", contract2.reload.status
    assert_match "2 contracts archived", flash[:notice]
  end

  test "bulk_export returns CSV of selected contracts" do
    post bulk_export_contracts_path, params: { ids: [ @contract.id ] }
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match @contract.title, response.body
    # Should NOT include non-selected contracts
    assert_no_match(/Landscaping/, response.body)
  end

  test "bulk_archive creates audit logs for each contract" do
    contract2 = contracts(:landscaping)
    assert_difference "AuditLog.count", 2 do
      post bulk_archive_contracts_path, params: { ids: [ @contract.id, contract2.id ] }
    end
    actions = AuditLog.order(created_at: :desc).limit(2).pluck(:action)
    assert actions.all? { |a| a == "updated" }
  end

  test "bulk_export creates audit log" do
    assert_difference "AuditLog.count" do
      post bulk_export_contracts_path, params: { ids: [ @contract.id ] }
    end
    assert_equal "exported", AuditLog.last.action
  end

  # Plan limit enforcement
  test "create blocked when at contract limit" do
    org = organizations(:one)
    org.update!(plan: "free")
    # Archive existing fixture contracts so we start clean
    org.contracts.update_all(status: "archived")
    # Create exactly 10 active contracts to hit the free plan limit
    10.times { |i| Contract.create!(title: "Filler #{i}", status: "active", organization: org) }

    assert_no_difference "Contract.count" do
      post contracts_path, params: {
        contract: {
          title: "Over Limit Contract",
          status: "active",
          contract_type: "software"
        }
      }
    end
    assert_redirected_to contracts_path
    assert_match "limit", flash[:alert]
  end

  test "create allowed when under contract limit" do
    org = organizations(:one)
    org.update!(plan: "free")

    assert_difference "Contract.count", 1 do
      post contracts_path, params: {
        contract: {
          title: "Under Limit Contract",
          status: "active",
          contract_type: "software"
        }
      }
    end
  end

  test "new action is blocked when at contract limit" do
    org = users(:one).memberships.first.organization
    org.update!(plan: "free")
    # Create contracts until at limit
    existing = org.active_contracts_count
    (10 - existing).times do |i|
      Contract.create!(title: "Filler #{i}", organization: org, status: "active", contract_type: "software")
    end
    assert org.reload.at_contract_limit?

    get new_contract_path
    assert_redirected_to contracts_path
    assert_match "Upgrade your plan", flash[:alert]
  end

  test "contract limit flash message contains pricing link" do
    org = users(:one).memberships.first.organization
    org.update!(plan: "free")
    existing = org.active_contracts_count
    (10 - existing).times do |i|
      Contract.create!(title: "Filler Link #{i}", organization: org, status: "active", contract_type: "software")
    end

    get new_contract_path
    assert_redirected_to contracts_path
    assert_match "href=", flash[:alert]
    assert_match "/pricing", flash[:alert]
  end

  test "contracts index shows usage context for non-pro plans" do
    org = users(:one).memberships.first.organization
    org.update!(plan: "free")
    get contracts_path
    assert_response :success
    assert_match "of 10 used", response.body
  end


  # Cross-tenant isolation for show/edit/update/destroy
  test "show returns not found for other org contract" do
    other_contract = contracts(:other_org_contract)
    get contract_path(other_contract)
    assert_redirected_to root_path
    assert_match "could not be found", flash[:alert]
  end

  test "edit returns not found for other org contract" do
    other_contract = contracts(:other_org_contract)
    get edit_contract_path(other_contract)
    assert_redirected_to root_path
    assert_match "could not be found", flash[:alert]
  end

  test "update returns not found for other org contract" do
    other_contract = contracts(:other_org_contract)
    patch contract_path(other_contract), params: {
      contract: { title: "Hacked Title" }
    }
    assert_redirected_to root_path
    other_contract.reload
    assert_equal "Office Lease", other_contract.title
  end

  test "destroy returns not found for other org contract" do
    other_contract = contracts(:other_org_contract)
    assert_no_difference "Contract.count" do
      delete contract_path(other_contract)
    end
    assert_redirected_to root_path
  end

  # Create with direction param
  test "create with direction param persists direction" do
    assert_difference "Contract.count", 1 do
      post contracts_path, params: {
        contract: {
          title: "Inbound Revenue Contract",
          direction: "inbound",
          status: "active"
        }
      }
    end
    contract = Contract.order(created_at: :desc).first
    assert_equal "inbound", contract.direction
  end

  # Create with document attachment
  test "create with document attachment creates contract_document" do
    assert_difference [ "Contract.count", "ContractDocument.count" ], 1 do
      post contracts_path, params: {
        contract: {
          title: "Contract With Doc",
          status: "active"
        },
        contract_documents: [ fixture_file_upload("test.txt", "text/plain") ]
      }
    end
    contract = Contract.order(created_at: :desc).first
    assert_equal 1, contract.contract_documents.count
  end

  # Create with legacy single-file param still works
  test "create with legacy single contract_document param creates document" do
    assert_difference [ "Contract.count", "ContractDocument.count" ], 1 do
      post contracts_path, params: {
        contract: {
          title: "Legacy Single File",
          status: "active"
        },
        contract_document: fixture_file_upload("test.txt", "text/plain")
      }
    end
    contract = Contract.order(created_at: :desc).first
    assert_equal 1, contract.contract_documents.count
  end

  # Create with multiple document attachments
  test "create with multiple documents creates one contract_document per file" do
    assert_difference "Contract.count", 1 do
      assert_difference "ContractDocument.count", 2 do
        post contracts_path, params: {
          contract: {
            title: "Multi-Doc Contract",
            status: "active"
          },
          contract_documents: [
            fixture_file_upload("test.txt", "text/plain"),
            fixture_file_upload("test.txt", "text/plain")
          ]
        }
      end
    end
    contract = Contract.order(created_at: :desc).first
    assert_equal 2, contract.contract_documents.count
  end

  # Update triggers GenerateContractAlertsJob when date fields change
  test "update enqueues alert job when end_date changes" do
    assert_enqueued_with(job: GenerateContractAlertsJob) do
      patch contract_path(@contract), params: {
        contract: { end_date: 2.years.from_now.to_date }
      }
    end
  end

  test "update does not enqueue alert job for non-date field changes" do
    clear_enqueued_jobs
    patch contract_path(@contract), params: {
      contract: { title: "Just a title change" }
    }
    assert_no_enqueued_jobs(only: GenerateContractAlertsJob)
  end

  # Combined filters
  test "index filters by status and type combined" do
    get contracts_path(status: "active", contract_type: "maintenance")
    assert_response :success
    assert_select "turbo-frame#contracts" do
      assert_select "a", text: "HVAC Maintenance - Building A"
      assert_select "a", text: "Landscaping Services", count: 0
      assert_select "a", text: "Property Insurance - Portfolio", count: 0
    end
  end

  test "index filters by status and search combined" do
    get contracts_path(status: "active", search: "HVAC")
    assert_response :success
    assert_select "turbo-frame#contracts" do
      assert_select "a", text: "HVAC Maintenance - Building A"
      assert_select "a", text: "Landscaping Services", count: 0
    end
  end

  # Direction filter
  test "index filters by direction" do
    get contracts_path(direction: "inbound")
    assert_response :success
    assert_select "turbo-frame#contracts" do
      assert_select "a", text: "Landscaping Services"
      assert_select "a", text: "HVAC Maintenance - Building A", count: 0
    end
  end

  # Bulk archive edge cases
  test "bulk_archive with empty ids redirects with alert" do
    post bulk_archive_contracts_path, params: { ids: [] }
    assert_redirected_to contracts_path
    assert_match "No contracts selected", flash[:alert]
  end

  test "bulk_archive with nil ids redirects with alert" do
    post bulk_archive_contracts_path
    assert_redirected_to contracts_path
    assert_match "No contracts selected", flash[:alert]
  end

  test "bulk_archive skips already-archived contracts" do
    @contract.update_column(:status, "archived")
    contract2 = contracts(:landscaping)
    post bulk_archive_contracts_path, params: { ids: [ @contract.id, contract2.id ] }
    assert_redirected_to contracts_path
    assert_match "1 contract archived", flash[:notice]
    assert_equal "archived", contract2.reload.status
  end

  test "bulk_archive with all already-archived contracts shows message" do
    @contract.update_column(:status, "archived")
    post bulk_archive_contracts_path, params: { ids: [ @contract.id ] }
    assert_redirected_to contracts_path
    assert_match "already archived", flash[:notice]
  end

  test "bulk_archive cancels pending alerts for archived contracts" do
    alert = Alert.create!(
      organization: organizations(:one),
      contract: @contract,
      alert_type: "renewal_upcoming",
      trigger_date: 30.days.from_now,
      status: "pending",
      message: "Test"
    )
    post bulk_archive_contracts_path, params: { ids: [ @contract.id ] }
    assert_equal "cancelled", alert.reload.status
  end

  # Bulk export edge case
  test "bulk_export with empty ids redirects with alert" do
    post bulk_export_contracts_path, params: { ids: [] }
    assert_redirected_to contracts_path
    assert_match "No contracts selected", flash[:alert]
  end

  # Destroy creates audit log
  test "destroy creates audit log with contract title" do
    title = @contract.title
    assert_difference "AuditLog.count" do
      delete contract_path(@contract)
    end
    log = AuditLog.order(created_at: :desc).first
    assert_equal "deleted", log.action
    assert_match title, log.details
  end

  # CSV includes notice_period_days
  test "CSV export includes notice_period_days column" do
    get contracts_path(format: :csv)
    assert_response :success
    assert_match "Notice Period Days", response.body
    assert_match @contract.notice_period_days.to_s, response.body
  end

  # Draft flow tests
  test "create_draft creates a draft contract and attaches documents" do
    assert_difference "Contract.count", 1 do
      assert_difference "ContractDocument.count", 1 do
        post create_draft_contracts_path, params: {
          contract_documents: [ fixture_file_upload("test.txt", "text/plain") ]
        }
      end
    end

    draft = Contract.order(created_at: :desc).first
    assert_equal "draft", draft.status
    assert_equal "Untitled Draft", draft.title
    assert_equal users(:one), draft.uploaded_by
    assert_equal 1, draft.contract_documents.count
    assert_redirected_to edit_contract_path(draft)
  end

  test "create_draft with multiple files creates multiple documents" do
    assert_difference "Contract.count", 1 do
      assert_difference "ContractDocument.count", 2 do
        post create_draft_contracts_path, params: {
          contract_documents: [
            fixture_file_upload("test.txt", "text/plain"),
            fixture_file_upload("test.txt", "text/plain")
          ]
        }
      end
    end

    draft = Contract.order(created_at: :desc).first
    assert_equal "draft", draft.status
    assert_equal 2, draft.contract_documents.count
  end

  test "create_draft without files redirects back with alert" do
    assert_no_difference "Contract.count" do
      post create_draft_contracts_path, params: { contract_documents: [] }
    end
    assert_redirected_to new_contract_path
    assert_match "upload at least one document", flash[:alert]
  end

  test "create_draft without params redirects back with alert" do
    assert_no_difference "Contract.count" do
      post create_draft_contracts_path
    end
    assert_redirected_to new_contract_path
  end

  test "drafts are excluded from index listing" do
    Contract.create!(title: "A Draft", status: "draft", organization: organizations(:one))
    get contracts_path
    assert_response :success
    # Draft should not appear in the contracts table
    assert_select "turbo-frame#contracts" do
      assert_select "a", text: "A Draft", count: 0
    end
  end

  test "drafts appear in drafts panel on index" do
    draft = Contract.create!(title: "My Draft", status: "draft", organization: organizations(:one))
    get contracts_path
    assert_response :success
    assert_match "Drafts", response.body
    assert_match "Continue", response.body
  end

  test "draft does not count toward contract limit" do
    org = organizations(:one)
    org.update!(plan: "free")
    org.contracts.update_all(status: "archived")
    # Create 10 active contracts (at limit)
    10.times { |i| Contract.create!(title: "Filler #{i}", status: "active", organization: org) }
    assert org.reload.at_contract_limit?

    # Should still be able to create a draft
    assert_difference "Contract.count", 1 do
      post create_draft_contracts_path, params: {
        contract_documents: [ fixture_file_upload("test.txt", "text/plain") ]
      }
    end
    assert_equal "draft", Contract.order(created_at: :desc).first.status
  end

  test "finalizing draft updates status and generates alerts" do
    draft = Contract.create!(
      title: "Untitled Draft",
      status: "draft",
      organization: organizations(:one),
      uploaded_by: users(:one)
    )

    assert_enqueued_with(job: GenerateContractAlertsJob) do
      patch contract_path(draft), params: {
        contract: {
          title: "Finalized Contract",
          status: "active",
          vendor_name: "Test Vendor"
        }
      }
    end

    draft.reload
    assert_equal "active", draft.status
    assert_equal "Finalized Contract", draft.title
    assert_redirected_to contract_path(draft)
    assert_match "successfully created", flash[:notice]
  end

  test "finalizing draft blocked when at contract limit" do
    org = organizations(:one)
    org.update!(plan: "free")
    org.contracts.where.not(status: "draft").update_all(status: "archived")
    10.times { |i| Contract.create!(title: "Filler #{i}", status: "active", organization: org) }

    draft = Contract.create!(
      title: "Untitled Draft",
      status: "draft",
      organization: org,
      uploaded_by: users(:one)
    )

    patch contract_path(draft), params: {
      contract: { title: "Finalized", status: "active" }
    }
    assert_response :unprocessable_entity
    assert_equal "draft", draft.reload.status
  end

  test "edit page shows finalize UI for draft contracts" do
    draft = Contract.create!(
      title: "Untitled Draft",
      status: "draft",
      organization: organizations(:one),
      uploaded_by: users(:one)
    )

    get edit_contract_path(draft)
    assert_response :success
    assert_match "Finalize Contract", response.body
    assert_match "Save Contract", response.body
  end

  test "new page shows upload-first layout" do
    get new_contract_path
    assert_response :success
    assert_match "Upload your contract", response.body
    assert_match "Skip upload, enter manually", response.body
  end

  test "index does not show draft status in filter options" do
    get contracts_path
    assert_response :success
    # The status filter dropdown should not include "Draft"
    assert_select "option[value='draft']", count: 0
  end
end
