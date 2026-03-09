require "test_helper"

class ContractReviewsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @organization = organizations(:one)
    @user = users(:one)
    sign_in_as @user

    @contract = contracts(:hvac_maintenance)
    @contract.contract_reviews.destroy_all
    @contract.update_columns(status: "in_review")

    ActsAsTenant.with_tenant(@organization) do
      @review = @contract.contract_reviews.create!(
        organization: @organization,
        status: "pending",
        review_type: "full",
        confidence_threshold: 80,
        total_fields: 0,
        reviewed_fields: 0
      )
    end
  end

  # --- show ---

  test "show renders review page" do
    create_field("title", "core", '"Office Lease"', status: "pending", confidence: 95, needs_review: false)
    finalize_review!

    get contract_contract_review_path(@contract)

    assert_response :success
  end

  test "show redirects if no active review" do
    @review.destroy!

    get contract_contract_review_path(@contract)

    assert_redirected_to contract_path(@contract)
    assert_equal "No active review found for this contract.", flash[:alert]
  end

  test "show marks pending review as in_progress" do
    create_field("title", "core", '"Office Lease"', status: "pending", confidence: 95, needs_review: false)
    finalize_review!
    assert_equal "pending", @review.status

    get contract_contract_review_path(@contract)

    assert_response :success
    assert_equal "in_progress", @review.reload.status
  end

  test "show does not change status of in_progress review" do
    create_field("title", "core", '"Office Lease"', status: "pending", confidence: 95, needs_review: false)
    finalize_review!
    @review.update!(status: "in_progress")

    get contract_contract_review_path(@contract)

    assert_response :success
    assert_equal "in_progress", @review.reload.status
  end

  test "show loads grouped fields" do
    create_field("title", "core", '"Office Lease"', status: "pending", confidence: 95, needs_review: false)
    create_field("monthly_value", "financial", "5400.00", status: "pending", confidence: 65, needs_review: true)
    finalize_review!

    get contract_contract_review_path(@contract)

    assert_response :success
    assert_match "Title", response.body
    assert_match "Monthly Value", response.body
  end

  # --- update_field ---

  test "update_field confirms a field" do
    field = create_field("title", "core", '"Office Lease"', status: "pending", confidence: 95, needs_review: false)
    finalize_review!
    @review.update!(status: "in_progress")

    patch update_field_contract_contract_review_path(@contract),
      params: { field_id: field.id, decision: "confirm" },
      as: :turbo_stream

    assert_response :success
    field.reload
    assert_equal "confirmed", field.status
    assert_equal @user.id, field.reviewed_by_id
    assert_not_nil field.reviewed_at
  end

  test "update_field edits a field with user_value" do
    field = create_field("monthly_value", "financial", "5400.00", status: "pending", confidence: 65, needs_review: true)
    finalize_review!
    @review.update!(status: "in_progress")

    patch update_field_contract_contract_review_path(@contract),
      params: { field_id: field.id, decision: "edit", user_value: "6000.00" },
      as: :turbo_stream

    assert_response :success
    field.reload
    assert_equal "edited", field.status
    assert_equal "6000.00", field.user_value
    assert_equal @user.id, field.reviewed_by_id
  end

  test "update_field marks not_found" do
    field = create_field("vendor_name", "core", nil, status: "pending", confidence: nil, needs_review: false)
    finalize_review!
    @review.update!(status: "in_progress")

    patch update_field_contract_contract_review_path(@contract),
      params: { field_id: field.id, decision: "not_found" },
      as: :turbo_stream

    assert_response :success
    assert_equal "not_found", field.reload.status
  end

  test "update_field marks not_applicable" do
    field = create_field("vendor_name", "core", nil, status: "pending", confidence: nil, needs_review: false)
    finalize_review!
    @review.update!(status: "in_progress")

    patch update_field_contract_contract_review_path(@contract),
      params: { field_id: field.id, decision: "not_applicable" },
      as: :turbo_stream

    assert_response :success
    assert_equal "not_applicable", field.reload.status
  end

  test "update_field updates reviewed count" do
    create_field("title", "core", '"Office Lease"', status: "confirmed", confidence: 95, needs_review: false)
    field = create_field("vendor_name", "core", '"Acme"', status: "pending", confidence: 90, needs_review: false)
    finalize_review!
    @review.update!(status: "in_progress")

    patch update_field_contract_contract_review_path(@contract),
      params: { field_id: field.id, decision: "confirm" },
      as: :turbo_stream

    assert_equal 2, @review.reload.reviewed_fields
  end

  test "update_field returns turbo_stream response" do
    field = create_field("title", "core", '"Office Lease"', status: "pending", confidence: 95, needs_review: false)
    finalize_review!
    @review.update!(status: "in_progress")

    patch update_field_contract_contract_review_path(@contract),
      params: { field_id: field.id, decision: "confirm" },
      as: :turbo_stream

    assert_response :success
    assert_equal Mime[:turbo_stream].to_s, response.media_type
    assert_includes response.body, 'target="review_panel"'
    assert_includes response.body, 'id="review_panel"'
    assert_includes response.body, "lg:w-1/2"
  end

  test "update_field re-renders panel and enables complete button after last required review" do
    field = create_field("monthly_value", "financial", "5400.00", status: "pending", confidence: 65, needs_review: true)
    finalize_review!
    @review.update!(status: "in_progress")

    patch update_field_contract_contract_review_path(@contract),
      params: { field_id: field.id, decision: "confirm" },
      as: :turbo_stream

    assert_response :success
    assert_includes response.body, 'target="review_panel"'
    refute_includes response.body, "cursor-not-allowed"
  end

  # --- bulk_accept ---

  test "bulk_accept accepts all confident pending fields" do
    create_field("title", "core", '"Office Lease"', status: "pending", confidence: 95, needs_review: false)
    create_field("vendor_name", "core", '"Acme"', status: "pending", confidence: 90, needs_review: false)
    finalize_review!
    @review.update!(status: "in_progress")

    post bulk_accept_contract_contract_review_path(@contract), as: :turbo_stream

    assert_response :success
    assert_includes response.body, 'target="review_panel"'
    assert_includes response.body, 'id="review_panel"'
    @review.fields.confident.reload.each do |field|
      assert_equal "auto_accepted", field.status
      assert_equal @user.id, field.reviewed_by_id
    end
  end

  test "bulk_accept updates reviewed count" do
    create_field("title", "core", '"Office Lease"', status: "pending", confidence: 95, needs_review: false)
    create_field("vendor_name", "core", '"Acme"', status: "pending", confidence: 90, needs_review: false)
    finalize_review!
    @review.update!(status: "in_progress")

    post bulk_accept_contract_contract_review_path(@contract), as: :turbo_stream

    assert_equal 2, @review.reload.reviewed_fields
  end

  test "bulk_accept does not affect needs_review fields" do
    confident = create_field("title", "core", '"Office Lease"', status: "pending", confidence: 95, needs_review: false)
    needs_review = create_field("monthly_value", "financial", "5400.00", status: "pending", confidence: 65, needs_review: true)
    finalize_review!
    @review.update!(status: "in_progress")

    post bulk_accept_contract_contract_review_path(@contract), as: :turbo_stream

    assert_equal "auto_accepted", confident.reload.status
    assert_equal "pending", needs_review.reload.status
  end

  # --- complete ---

  test "complete happy path completes review and activates contract" do
    create_field("title", "core", '"Office Lease"', status: "confirmed", confidence: 95, needs_review: false)
    finalize_review!
    @review.update!(status: "in_progress")

    post complete_contract_contract_review_path(@contract)

    assert_redirected_to contract_path(@contract)
    assert_equal "completed", @review.reload.status
    assert_equal "active", @contract.reload.status
  end

  test "complete enqueues GenerateContractAlertsJob" do
    create_field("title", "core", '"Office Lease"', status: "confirmed", confidence: 95, needs_review: false)
    finalize_review!
    @review.update!(status: "in_progress")

    assert_enqueued_with(job: GenerateContractAlertsJob, args: [ @contract.id ]) do
      post complete_contract_contract_review_path(@contract)
    end
  end

  test "complete fails if required needs_review fields still pending" do
    create_field("monthly_value", "financial", "5400.00", status: "pending", confidence: 65, needs_review: true)
    finalize_review!
    @review.update!(status: "in_progress")

    post complete_contract_contract_review_path(@contract)

    assert_redirected_to contract_contract_review_path(@contract)
    assert_match(/not all required fields/i, flash[:alert])
    assert_not_equal "completed", @review.reload.status
  end

  # --- save_draft ---

  test "save_draft returns success" do
    create_field("title", "core", '"Office Lease"', status: "pending", confidence: 95, needs_review: false)
    finalize_review!
    @review.update!(status: "in_progress")

    post save_draft_contract_contract_review_path(@contract), as: :turbo_stream

    assert_response :success
  end

  # --- Guards ---

  test "requires authentication" do
    sign_out
    get contract_contract_review_path(@contract)
    assert_redirected_to new_session_path
  end

  private

  def create_field(field_name, group, value, status:, confidence:, needs_review: false, user_value: nil)
    catalog = ReviewFieldCatalog.find(field_name) || ReviewFieldCatalog.find(field_name.split(".").last)
    display = catalog&.display_name || field_name.humanize

    @review.fields.create!(
      field_name: field_name,
      field_group: group,
      display_name: display,
      extracted_value: value,
      confidence: confidence,
      needs_review: needs_review,
      status: status,
      user_value: user_value,
      reviewed_at: status == "pending" ? nil : Time.current,
      position: @review.fields.count
    )
  end

  def finalize_review!
    @review.update!(
      total_fields: @review.fields.count,
      reviewed_fields: @review.fields.reviewed.count
    )
  end
end
