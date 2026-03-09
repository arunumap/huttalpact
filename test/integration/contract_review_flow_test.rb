require "test_helper"

class ContractReviewFlowTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @organization = organizations(:one)
    @user = users(:one)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  def sample_ai_response
    {
      "title" => "Test Office Lease",
      "vendor_name" => "Acme Properties",
      "start_date" => "2025-01-01",
      "end_date" => "2027-12-31",
      "monthly_value" => 5400,
      "annual_value" => 64800,
      "total_value" => 194400,
      "contract_type" => "lease",
      "field_metadata" => {
        "title" => { "confidence" => 95, "source_excerpt" => "Test Office Lease Agreement", "reasoning" => "Clear title" },
        "vendor_name" => { "confidence" => 90, "source_excerpt" => "Acme Properties LLC", "reasoning" => "Named as landlord" },
        "start_date" => { "confidence" => 85, "source_excerpt" => "January 1, 2025", "reasoning" => "Commencement date" },
        "end_date" => { "confidence" => 88, "source_excerpt" => "December 31, 2027", "reasoning" => "Expiration date" },
        "monthly_value" => { "confidence" => 60, "source_excerpt" => "$5,400 per month", "reasoning" => "Year 1 rent" },
        "total_value" => { "confidence" => 50, "source_excerpt" => "total consideration", "reasoning" => "Calculated from term and rent" },
        "contract_type" => { "confidence" => 92, "source_excerpt" => "Lease Agreement", "reasoning" => "Document is a lease" }
      }
    }
  end

  def create_contract_for_review(status: "draft", contract_type: "lease")
    Contract.create!(
      organization: @organization,
      title: "Review Test Contract",
      vendor_name: "Original Vendor",
      status: status,
      contract_type: contract_type,
      direction: "outbound",
      start_date: Date.new(2024, 1, 1),
      end_date: Date.new(2025, 12, 31),
      monthly_value: 1000,
      total_value: 24000,
      extraction_status: "completed",
      uploaded_by: @user
    )
  end

  def create_review_for(contract, ai_response: sample_ai_response, mode: :full)
    ContractReviewCreatorService.new(
      contract: contract,
      extracted_data: ai_response,
      mode: mode
    ).call
  end

  def confirm_all_needs_review_fields!(review)
    review.fields.needs_review.pending.find_each do |field|
      patch update_field_contract_contract_review_path(review.contract),
            params: { field_id: field.id, decision: "confirm" }
    end
  end

  # ---------------------------------------------------------------------------
  # End-to-end flow tests
  # ---------------------------------------------------------------------------

  test "full review flow: create review, confirm fields, bulk accept, complete" do
    contract = create_contract_for_review
    review = create_review_for(contract)

    assert_equal "in_review", contract.reload.status
    assert_equal "pending", review.status
    assert review.fields.count > 0

    # Visit review page — marks review in_progress
    get contract_contract_review_path(contract)
    assert_response :success
    assert_equal "in_progress", review.reload.status

    # Confirm needs_review fields one by one
    confirm_all_needs_review_fields!(review)
    review.reload
    assert review.fields.needs_review.pending.none?

    # Bulk accept confident fields
    post bulk_accept_contract_contract_review_path(contract)
    review.reload
    assert review.fields.confident.pending.none?

    # Complete the review
    assert_enqueued_with(job: GenerateContractAlertsJob) do
      post complete_contract_contract_review_path(contract)
    end

    assert_redirected_to contract_path(contract)
    contract.reload
    review.reload

    assert_equal "completed", review.status
    assert_equal "active", contract.status
    assert_equal "Test Office Lease", contract.title
    assert_equal "Acme Properties", contract.vendor_name
    assert_equal Date.new(2025, 1, 1), contract.start_date
    assert_equal Date.new(2027, 12, 31), contract.end_date
    assert_equal 5400.0, contract.monthly_value.to_f
    assert_equal 194400.0, contract.total_value.to_f
  end

  test "edit flow: edit a field with new value then complete" do
    contract = create_contract_for_review
    review = create_review_for(contract)

    get contract_contract_review_path(contract)

    # Edit the title field
    title_field = review.fields.find_by!(field_name: "title")
    patch update_field_contract_contract_review_path(contract),
          params: { field_id: title_field.id, decision: "edit", user_value: '"Edited Lease Title"' }

    title_field.reload
    assert_equal "edited", title_field.status
    assert_equal '"Edited Lease Title"', title_field.user_value

    # Confirm remaining needs_review fields
    confirm_all_needs_review_fields!(review)

    post complete_contract_contract_review_path(contract)
    contract.reload

    assert_equal "active", contract.status
    assert_equal "Edited Lease Title", contract.title
  end

  test "not_found flow: mark field as not_found then complete" do
    contract = create_contract_for_review
    review = create_review_for(contract)

    get contract_contract_review_path(contract)

    # Mark total_value as not_found (it's needs_review with confidence 50)
    total_field = review.fields.find_by!(field_name: "total_value")
    assert total_field.needs_review?

    patch update_field_contract_contract_review_path(contract),
          params: { field_id: total_field.id, decision: "not_found" }

    total_field.reload
    assert_equal "not_found", total_field.status

    # Confirm remaining needs_review fields
    confirm_all_needs_review_fields!(review)

    post complete_contract_contract_review_path(contract)
    contract.reload

    assert_equal "active", contract.status
    # not_found fields are not applied — but original contract value was 24000, and
    # parse_final_value returns nil for not_found. The completion service only updates
    # fields that are not nil AND not not_found/not_applicable, so original value stays
    # unless the completion service explicitly sets nil.
    # Actually: the completion service skips nil + not_found/not_applicable fields.
    assert_nil total_field.reload.final_value
  end

  test "incremental review only shows changed fields" do
    contract = create_contract_for_review(status: "active")
    contract.update!(title: "Test Office Lease", vendor_name: "Acme Properties")

    # Incremental extraction with same title/vendor but different monthly_value
    incremental_response = sample_ai_response.merge(
      "monthly_value" => 6000,
      "field_metadata" => sample_ai_response["field_metadata"].merge(
        "monthly_value" => { "confidence" => 60, "source_excerpt" => "$6,000 per month", "reasoning" => "Updated rent" }
      )
    )

    review = create_review_for(contract, ai_response: incremental_response, mode: :incremental)
    contract.reload

    assert_equal "in_review", contract.status

    # Incremental review should only include fields that changed
    field_names = review.fields.pluck(:field_name)
    assert_includes field_names, "monthly_value"
    # title/vendor_name should NOT be included since they match current values
    assert_not_includes field_names, "title"
    assert_not_includes field_names, "vendor_name"
  end

  # ---------------------------------------------------------------------------
  # Pipeline integration tests
  # ---------------------------------------------------------------------------

  test "AiExtractContractJob creates review when extraction succeeds" do
    contract = create_contract_for_review(status: "draft")

    mock_extractor = Minitest::Mock.new
    mock_extractor.expect(:call, nil)

    # After the extractor runs, simulate completed extraction with data
    ContractAiExtractorService.stub(:new, ->(_contract, **_opts) {
      contract.update!(
        extraction_status: "completed",
        ai_extracted_data: sample_ai_response.to_json
      )
      mock_extractor
    }) do
      AiExtractContractJob.perform_now(contract.id)
    end

    contract.reload
    assert_equal "in_review", contract.status

    review = contract.current_review
    assert_not_nil review
    assert_equal "full", review.review_type
    assert review.fields.count > 0

    mock_extractor.verify
  end

  test "failed extraction does not create review" do
    contract = create_contract_for_review(status: "draft")
    contract.update!(extraction_status: "failed")
    original_review_count = contract.contract_reviews.count

    mock_extractor = Minitest::Mock.new
    mock_extractor.expect(:call, nil)

    # Extractor runs but leaves extraction_status as "failed"
    ContractAiExtractorService.stub(:new, ->(_contract, **_opts) {
      contract.update!(extraction_status: "failed", ai_extracted_data: nil)
      mock_extractor
    }) do
      AiExtractContractJob.perform_now(contract.id)
    end

    contract.reload
    assert_equal "failed", contract.extraction_status
    assert_equal original_review_count, contract.contract_reviews.count
  end

  # ---------------------------------------------------------------------------
  # Guard tests
  # ---------------------------------------------------------------------------

  test "contract show redirects to review when in_review" do
    contract = create_contract_for_review
    create_review_for(contract)
    assert_equal "in_review", contract.reload.status

    get contract_path(contract)
    assert_redirected_to contract_contract_review_path(contract)
  end

  test "contract edit blocked during review" do
    contract = create_contract_for_review
    create_review_for(contract)

    get edit_contract_path(contract)
    assert_redirected_to contract_contract_review_path(contract)
  end

  test "document upload blocked during review" do
    contract = create_contract_for_review
    create_review_for(contract)

    post contract_documents_path(contract), params: {
      file: fixture_file_upload("test/fixtures/files/sample.pdf", "application/pdf")
    }
    assert_redirected_to contract_contract_review_path(contract)
    assert_match(/in review/, flash[:alert])
  end

  test "lease detail edit blocked during review" do
    contract = create_contract_for_review(contract_type: "lease")
    contract.create_lease_detail!
    create_review_for(contract)

    get edit_contract_lease_detail_path(contract)
    assert_redirected_to contract_contract_review_path(contract)
    assert_match(/in review/, flash[:alert])
  end

  test "re-extraction blocked during review" do
    contract = create_contract_for_review
    create_review_for(contract)

    post contract_extraction_path(contract)
    assert_redirected_to contract_contract_review_path(contract)
    assert_match(/review/, flash[:alert])
  end

  # ---------------------------------------------------------------------------
  # Edge case tests
  # ---------------------------------------------------------------------------

  test "completion is idempotent — completing again raises error" do
    contract = create_contract_for_review
    review = create_review_for(contract)

    get contract_contract_review_path(contract)
    confirm_all_needs_review_fields!(review)
    post complete_contract_contract_review_path(contract)
    assert_equal "completed", review.reload.status

    # The contract is now active and review is completed.
    # current_review returns nil (no active review), so set_review redirects.
    get contract_contract_review_path(contract)
    assert_redirected_to contract_path(contract)
    follow_redirect!

    # Attempting to complete again also redirects because no active review exists
    post complete_contract_contract_review_path(contract)
    assert_redirected_to contract_path(contract)
  end

  test "save draft preserves state and fields retain their reviewed status" do
    contract = create_contract_for_review
    review = create_review_for(contract)

    get contract_contract_review_path(contract)

    # Confirm one field
    title_field = review.fields.find_by!(field_name: "title")
    patch update_field_contract_contract_review_path(contract),
          params: { field_id: title_field.id, decision: "confirm" }

    # Save draft
    post save_draft_contract_contract_review_path(contract)

    # Re-visit — field should still be confirmed
    get contract_contract_review_path(contract)
    assert_response :success
    assert_equal "confirmed", title_field.reload.status
    assert_equal "in_progress", review.reload.status
  end

  test "completion fails when needs_review fields are still pending" do
    contract = create_contract_for_review
    review = create_review_for(contract)

    get contract_contract_review_path(contract)

    # Don't review any needs_review fields — attempt completion directly
    assert review.fields.needs_review.pending.any?, "Expected unreviewed needs_review fields"

    post complete_contract_contract_review_path(contract)
    assert_redirected_to contract_contract_review_path(contract)
    assert_match(/reviewed/, flash[:alert])

    # Contract should NOT be active
    assert_not_equal "active", contract.reload.status
  end
end
