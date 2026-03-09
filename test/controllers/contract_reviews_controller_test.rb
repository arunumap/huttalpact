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

  # --- milestone editing ---

  test "update_milestone edits a milestone entry without raw user_value input" do
    field = create_field(
      "lease_milestones",
      "milestones",
      [
        { "milestone_type" => "custom", "due_date" => "2025-05-01", "description" => "Original", "recurring" => false }
      ].to_json,
      status: "pending",
      confidence: 60,
      needs_review: true
    )
    finalize_review!
    @review.update!(status: "in_progress")

    patch update_milestone_contract_contract_review_path(@contract),
      params: {
        field_id: field.id,
        milestone_index: 0,
        open_milestone_drawer_id: "drawer_1",
        milestone: {
          milestone_type: "insurance_renewal",
          due_date: "2025-06-15",
          description: "Updated milestone",
          recurring: "1",
          recurrence_interval: "annual"
        }
      },
      as: :turbo_stream

    assert_response :success
    assert_includes response.body, 'target="review_panel"'

    field.reload
    assert_equal "edited", field.status
    assert_equal @user.id, field.reviewed_by_id

    parsed = JSON.parse(field.user_value)
    assert_equal 1, parsed.length
    assert_equal "insurance_renewal", parsed.first["milestone_type"]
    assert_equal "2025-06-15", parsed.first["due_date"]
    assert_equal "Updated milestone", parsed.first["description"]
    assert_equal true, parsed.first["recurring"]
    assert_equal "annual", parsed.first["recurrence_interval"]
  end

  test "remove_milestone deletes one milestone entry" do
    field = create_field(
      "lease_milestones",
      "milestones",
      [
        { "milestone_type" => "custom", "due_date" => "2025-05-01", "description" => "One", "recurring" => false },
        { "milestone_type" => "insurance_renewal", "due_date" => "2025-08-01", "description" => "Two", "recurring" => true, "recurrence_interval" => "annual" }
      ].to_json,
      status: "pending",
      confidence: 60,
      needs_review: true
    )
    finalize_review!
    @review.update!(status: "in_progress")

    delete remove_milestone_contract_contract_review_path(@contract),
      params: { field_id: field.id, milestone_index: 0, open_milestone_drawer_id: "drawer_1" },
      as: :turbo_stream

    assert_response :success
    assert_includes response.body, 'target="review_panel"'

    parsed = JSON.parse(field.reload.user_value)
    assert_equal 1, parsed.length
    assert_equal "insurance_renewal", parsed.first["milestone_type"]
  end

  test "update_milestone redirects with alert for invalid payload" do
    field = create_field(
      "lease_milestones",
      "milestones",
      [
        { "milestone_type" => "custom", "due_date" => "2025-05-01", "description" => "Original", "recurring" => false }
      ].to_json,
      status: "pending",
      confidence: 60,
      needs_review: true
    )
    finalize_review!
    @review.update!(status: "in_progress")

    patch update_milestone_contract_contract_review_path(@contract),
      params: {
        field_id: field.id,
        milestone_index: 0,
        milestone: {
          milestone_type: "invalid_type",
          due_date: "2025-06-15",
          description: "Bad",
          recurring: "0",
          recurrence_interval: ""
        }
      }

    assert_redirected_to contract_contract_review_path(@contract)
    assert_match(/Milestone type is invalid/i, flash[:alert])
  end

  # --- key clause editing ---

  test "update_key_clause edits a key clause entry without raw user_value input" do
    field = create_field(
      "key_clauses",
      "clauses",
      [
        {
          "clause_type" => "termination",
          "content" => "Either party may terminate with 30 days notice.",
          "page_reference" => "Section 9",
          "confidence_score" => 72,
          "source_excerpt" => "Either party may terminate with 30 days notice.",
          "source_locator" => { "document_id" => "doc-1", "start_offset" => 10, "end_offset" => 54 },
          "evidence_status" => "grounded"
        }
      ].to_json,
      status: "pending",
      confidence: 60,
      needs_review: true
    )
    finalize_review!
    @review.update!(status: "in_progress")

    patch update_key_clause_contract_contract_review_path(@contract),
      params: {
        field_id: field.id,
        key_clause_index: 0,
        open_key_clause_drawer_id: "drawer_2",
        key_clause: {
          clause_type: "renewal",
          content: "Agreement renews for one additional year unless either party opts out.",
          page_reference: "Section 10",
          confidence_score: "88"
        }
      },
      as: :turbo_stream

    assert_response :success
    assert_includes response.body, 'target="review_panel"'

    field.reload
    assert_equal "edited", field.status
    assert_equal @user.id, field.reviewed_by_id

    parsed = JSON.parse(field.user_value)
    assert_equal 1, parsed.length
    assert_equal "renewal", parsed.first["clause_type"]
    assert_equal "Section 10", parsed.first["page_reference"]
    assert_equal 88, parsed.first["confidence_score"]
    assert_equal "doc-1", parsed.first["source_locator"]["document_id"]
  end

  test "remove_key_clause deletes one key clause entry" do
    field = create_field(
      "key_clauses",
      "clauses",
      [
        { "clause_type" => "termination", "content" => "30 day notice" },
        { "clause_type" => "renewal", "content" => "Automatic annual renewal" }
      ].to_json,
      status: "pending",
      confidence: 60,
      needs_review: true
    )
    finalize_review!
    @review.update!(status: "in_progress")

    delete remove_key_clause_contract_contract_review_path(@contract),
      params: { field_id: field.id, key_clause_index: 0, open_key_clause_drawer_id: "drawer_2" },
      as: :turbo_stream

    assert_response :success
    assert_includes response.body, 'target="review_panel"'

    parsed = JSON.parse(field.reload.user_value)
    assert_equal 1, parsed.length
    assert_equal "renewal", parsed.first["clause_type"]
  end

  test "update_key_clause redirects with alert for invalid payload" do
    field = create_field(
      "key_clauses",
      "clauses",
      [
        { "clause_type" => "termination", "content" => "30 day notice" }
      ].to_json,
      status: "pending",
      confidence: 60,
      needs_review: true
    )
    finalize_review!
    @review.update!(status: "in_progress")

    patch update_key_clause_contract_contract_review_path(@contract),
      params: {
        field_id: field.id,
        key_clause_index: 0,
        key_clause: {
          clause_type: "invalid_type",
          content: "Bad clause"
        }
      }

    assert_redirected_to contract_contract_review_path(@contract)
    assert_match(/Clause type is invalid/i, flash[:alert])
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

  test "complete ingests learning events once per reviewed field" do
    source_document = contract_documents(:completed_doc)
    create_field(
      "title",
      "core",
      '"Office Lease"',
      status: "confirmed",
      confidence: 95,
      needs_review: false,
      source_excerpt: "Office Lease",
      source_locator: {
        "document_id" => source_document.id,
        "start_offset" => 0,
        "end_offset" => 12,
        "matched_text" => "Office Lease"
      },
      source_match_strategy: "exact",
      source_document: source_document
    )
    create_field("vendor_name", "core", '"Acme"', status: "edited", confidence: 60, needs_review: true, user_value: '"Acme LLC"')
    create_field("total_value", "financial", nil, status: "not_found", confidence: nil, needs_review: false)
    create_field("notice_period_days", "financial", nil, status: "not_applicable", confidence: nil, needs_review: false)
    finalize_review!
    @review.update!(status: "in_progress")

    assert_difference "ReviewLearningEvent.count", 4 do
      post complete_contract_contract_review_path(@contract)
    end

    decisions = ReviewLearningEvent.where(contract_review: @review).pluck(:decision)
    assert_equal %w[confirmed edited not_applicable not_found], decisions.sort
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

  def create_field(field_name, group, value, status:, confidence:, needs_review: false, user_value: nil,
    source_excerpt: nil, source_locator: nil, source_match_strategy: nil, source_document: nil)
    catalog = ReviewFieldCatalog.find(field_name) || ReviewFieldCatalog.find(field_name.split(".").last)
    display = catalog&.display_name || field_name.humanize

    @review.fields.create!(
      field_name: field_name,
      field_group: group,
      display_name: display,
      extracted_value: value,
      confidence: confidence,
      source_excerpt: source_excerpt,
      source_locator: source_locator,
      source_match_strategy: source_match_strategy,
      needs_review: needs_review,
      status: status,
      user_value: user_value,
      reviewed_at: status == "pending" ? nil : Time.current,
      reviewed_by: status == "pending" ? nil : @user,
      source_document: source_document,
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
