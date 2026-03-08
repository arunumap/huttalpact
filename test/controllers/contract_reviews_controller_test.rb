require "test_helper"

class ContractReviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @contract = contracts(:hvac_maintenance)
    @contract.update!(status: "in_review")
    @review = ActsAsTenant.with_tenant(@contract.organization) do
      @contract.contract_reviews.create!(organization: @contract.organization, review_trigger: "initial_extraction")
    end
    @review.contract_review_fields.create!(
      contract: @contract,
      organization: @contract.organization,
      field_key: "contract.end_date",
      extracted_value: "2028-12-31",
      readiness_bucket: "looks_good"
    )
  end

  test "shows the review workspace" do
    get contract_review_path(@contract)

    assert_response :success
    assert_match "Human review", response.body
    assert_match "Complete review", response.body
    assert_match "End Date", response.body
  end

  test "save progress records audit history" do
    assert_difference -> { AuditLog.where(action: "review_progress_saved", contract: @contract).count }, 1 do
      patch save_progress_contract_review_path(@contract)
    end

    assert_redirected_to contract_review_path(@contract)
  end

  test "complete redirects back to review when blockers remain" do
    @review.contract_review_fields.create!(
      contract: @contract,
      organization: @contract.organization,
      field_key: "contract.notice_period_days",
      extracted_value: nil,
      readiness_bucket: "blocked"
    )

    patch complete_contract_review_path(@contract)

    assert_redirected_to contract_review_path(@contract)
    assert_match "Resolve 1 blocking item", flash[:alert]
    assert_equal "open", @review.reload.status
  end

  test "shows extraction shell for draft contracts before a review exists" do
    draft = Contract.create!(
      title: "Untitled Draft",
      status: "draft",
      organization: organizations(:one),
      uploaded_by: users(:one)
    )
    draft.contract_documents.create!(
      extraction_status: "pending",
      document_type: "main_contract",
      position: 0,
      file: fixture_file_upload("test.txt", "text/plain")
    )

    get contract_review_path(draft)

    assert_response :success
    assert_match "Preparing human review", response.body
    assert_match "AI is extracting your contract details", response.body
    assert_no_match(/Complete review/, response.body)
  end

  test "workspace partial renders through application renderer when review exists" do
    html = ApplicationController.render(
      partial: "contract_reviews/workspace",
      locals: { contract: @contract, review: @review }
    )

    assert_includes html, "Human review"
    assert_includes html, "Complete review"
  end
end
