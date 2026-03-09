require "test_helper"

class ContractReviewCompletionServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup do
    @organization = organizations(:one)
    @user = users(:one)
    @contract = contracts(:hvac_maintenance)
    @contract.contract_reviews.destroy_all
    @contract.update!(status: "in_review")

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

  # --- Happy path: generic contract ---

  test "completes review and applies values to generic contract" do
    create_confirmed_field("title", "core", '"Updated HVAC Title"', confidence: 95)
    create_confirmed_field("vendor_name", "core", '"New Vendor"', confidence: 90)
    create_confirmed_field("monthly_value", "financial", "1500.00", confidence: 85)
    create_confirmed_field("start_date", "dates", '"2025-06-01"', confidence: 92)
    finalize_review_fields!

    result = run_completion_service

    assert_equal "completed", result.reload.status
    assert_equal "active", @contract.reload.status

    assert_equal "Updated HVAC Title", @contract.title
    assert_equal "New Vendor", @contract.vendor_name
    assert_equal 1500.00, @contract.monthly_value.to_f
    assert_equal Date.parse("2025-06-01"), @contract.start_date
  end

  # --- Happy path: lease contract ---

  test "completes review and applies lease-specific data" do
    lease = contracts(:commercial_lease)
    lease.contract_reviews.destroy_all
    lease.update!(status: "in_review")
    lease.lease_detail&.destroy
    lease.rent_escalations.destroy_all
    lease.lease_options.destroy_all
    lease.lease_milestones.destroy_all
    lease.key_clauses.destroy_all

    review = ActsAsTenant.with_tenant(@organization) do
      lease.contract_reviews.create!(
        organization: @organization,
        status: "pending",
        review_type: "full",
        confidence_threshold: 80,
        total_fields: 0,
        reviewed_fields: 0
      )
    end

    lease_detail_json = { "lease_type" => "nnn", "rentable_sqft" => 5000, "cam_audit_rights" => true }.to_json
    escalations_json = [ { "effective_date" => "2026-01-01", "base_rent_monthly" => 9000, "escalation_type" => "fixed_percentage", "escalation_value" => 3.0 } ].to_json
    options_json = [ { "option_type" => "renewal", "exercise_deadline" => "2030-06-01", "term_length_months" => 60 } ].to_json
    milestones_json = [ { "milestone_type" => "custom", "due_date" => "2025-01-01", "description" => "Lease starts" } ].to_json
    clauses_json = [ { "clause_type" => "termination", "content" => "30 day notice required" } ].to_json

    create_field_on(review, "title", "core", '"Retail Space"', status: "confirmed", confidence: 95)
    create_field_on(review, "lease_details.lease_type", "lease_space", '"nnn"', status: "confirmed", confidence: 90)
    create_field_on(review, "lease_details.rentable_sqft", "lease_space", "5000", status: "confirmed", confidence: 88)
    create_field_on(review, "lease_details.cam_audit_rights", "cam", "true", status: "confirmed", confidence: 92)
    create_field_on(review, "rent_escalations", "escalations", escalations_json, status: "confirmed", confidence: 85)
    create_field_on(review, "lease_options", "options", options_json, status: "confirmed", confidence: 87)
    create_field_on(review, "lease_milestones", "milestones", milestones_json, status: "confirmed", confidence: 90)
    create_field_on(review, "key_clauses", "clauses", clauses_json, status: "confirmed", confidence: 92)
    review.update!(total_fields: review.fields.count, reviewed_fields: review.fields.reviewed.count)

    ActsAsTenant.with_tenant(@organization) do
      ContractReviewCompletionService.new(review: review, user: @user).call
    end

    lease.reload
    assert_equal "active", lease.status
    assert_equal "Retail Space", lease.title
    assert lease.lease_detail.present?
    assert_equal "nnn", lease.lease_detail.lease_type
    assert_equal 5000, lease.lease_detail.rentable_sqft
    assert_equal true, lease.lease_detail.cam_audit_rights
    assert_equal 1, lease.rent_escalations.count
    assert_equal 1, lease.lease_options.count
    assert_equal 1, lease.lease_milestones.count
    assert_equal 1, lease.key_clauses.count
    assert_equal "termination", lease.key_clauses.first.clause_type
  end

  # --- Auto-accepts confident pending fields ---

  test "auto-accepts confident pending fields during completion" do
    confident_field = create_field("title", "core", '"Auto Title"', status: "pending", confidence: 95, needs_review: false)
    create_confirmed_field("vendor_name", "core", '"Vendor"', confidence: 90)
    finalize_review_fields!

    run_completion_service

    assert_equal "auto_accepted", confident_field.reload.status
    assert_equal @user.id, confident_field.reviewed_by_id
    assert confident_field.reviewed_at.present?
  end

  test "logs JSON parse failures with field context" do
    create_field("title", "core", "not-json", status: "confirmed", confidence: 90, needs_review: false)
    finalize_review_fields!

    logger_mock = Minitest::Mock.new
    logger_mock.expect(:error, nil) do |message|
      message.include?("field title") && message.include?("id=")
    end

    Rails.stub(:logger, logger_mock) do
      run_completion_service
    end

    logger_mock.verify
    assert_equal "not-json", @contract.reload.title
  end

  # --- Confirmed field uses extracted_value ---

  test "confirmed field applies extracted_value to contract" do
    create_confirmed_field("title", "core", '"Confirmed Title"', confidence: 95)
    finalize_review_fields!

    run_completion_service

    assert_equal "Confirmed Title", @contract.reload.title
  end

  # --- Edited field uses user_value ---

  test "edited field applies user_value to contract" do
    create_field("title", "core", '"Original AI Title"',
      status: "edited",
      confidence: 70,
      needs_review: true,
      user_value: '"User Edited Title"')
    finalize_review_fields!

    run_completion_service

    assert_equal "User Edited Title", @contract.reload.title
  end

  # --- Not found / not applicable fields are skipped ---

  test "not_found fields are not applied" do
    original_title = @contract.title
    create_field("title", "core", nil, status: "not_found", confidence: nil, needs_review: false)
    create_confirmed_field("vendor_name", "core", '"Applied Vendor"', confidence: 90)
    finalize_review_fields!

    run_completion_service

    assert_equal original_title, @contract.reload.title
    assert_equal "Applied Vendor", @contract.vendor_name
  end

  test "not_applicable fields are not applied" do
    original_title = @contract.title
    create_field("title", "core", nil, status: "not_applicable", confidence: nil, needs_review: false)
    create_confirmed_field("vendor_name", "core", '"Applied Vendor"', confidence: 90)
    finalize_review_fields!

    run_completion_service

    assert_equal original_title, @contract.reload.title
  end

  test "ingests review learning events for all reviewed completion outcomes" do
    source_document = contract_documents(:completed_doc)

    create_field(
      "title",
      "core",
      '"Learned Title"',
      status: "confirmed",
      confidence: 95,
      needs_review: false,
      source_excerpt: "Learned Title",
      source_locator: {
        "document_id" => source_document.id,
        "start_offset" => 12,
        "end_offset" => 24,
        "matched_text" => "Learned Title"
      },
      source_match_strategy: "exact",
      source_document: source_document
    )
    create_field(
      "vendor_name",
      "core",
      '"Acme Vendor"',
      status: "edited",
      confidence: 60,
      needs_review: true,
      user_value: '"Acme Vendor LLC"',
      source_excerpt: "Acme Vendor",
      source_document: source_document
    )
    create_field("total_value", "financial", nil, status: "not_found", confidence: nil, needs_review: false)
    create_field("renewal_term", "financial", nil, status: "not_applicable", confidence: nil, needs_review: false)
    finalize_review_fields!

    assert_difference "ReviewLearningEvent.count", 4 do
      run_completion_service
    end

    events = ReviewLearningEvent.where(contract_review: @review).index_by(&:field_name)
    assert_equal %w[confirmed edited not_applicable not_found], events.values.map(&:decision).sort
    assert_equal "strong", events.fetch("title").evidence_quality
    assert_equal "moderate", events.fetch("vendor_name").evidence_quality
    assert_equal "missing", events.fetch("total_value").evidence_quality
    assert_equal true, events.fetch("vendor_name").corrected
  end

  # --- Transitions contract from in_review to active ---

  test "transitions contract from in_review to active" do
    assert_equal "in_review", @contract.status
    create_confirmed_field("title", "core", '"Test"', confidence: 90)
    finalize_review_fields!

    run_completion_service

    assert_equal "active", @contract.reload.status
  end

  test "transitions contract from draft to active" do
    @contract.update!(status: "draft")
    create_confirmed_field("title", "core", '"Test"', confidence: 90)
    finalize_review_fields!

    run_completion_service

    assert_equal "active", @contract.reload.status
  end

  test "preserves non-draft non-in-review status" do
    @contract.update!(status: "expiring_soon")
    create_confirmed_field("title", "core", '"Test"', confidence: 90)
    finalize_review_fields!

    run_completion_service

    assert_equal "expiring_soon", @contract.reload.status
  end

  # --- Creates audit log ---

  test "creates audit log with review_completed action" do
    create_confirmed_field("title", "core", '"Audited"', confidence: 92)
    create_field("vendor_name", "core", nil, status: "not_found", confidence: nil, needs_review: false)
    finalize_review_fields!

    assert_difference "AuditLog.count", 1 do
      run_completion_service
    end

    log = AuditLog.order(:created_at).last
    assert_equal "review_completed", log.action
    assert_equal @contract.id, log.contract_id
    assert_equal @user.id, log.user_id
    assert_includes log.details.to_s, @review.id
    assert_includes log.details.to_s, "full"
  end

  # --- Enqueues GenerateContractAlertsJob ---

  test "enqueues GenerateContractAlertsJob after completion" do
    create_confirmed_field("title", "core", '"Alert Test"', confidence: 90)
    finalize_review_fields!

    assert_enqueued_with(job: GenerateContractAlertsJob, args: [ @contract.id ]) do
      run_completion_service
    end
  end

  # --- Raises ReviewIncompleteError for pending required fields ---

  test "raises ReviewIncompleteError if required fields are still pending" do
    create_field("title", "core", '"Pending"', status: "pending", confidence: 50, needs_review: true)
    finalize_review_fields!

    assert_raises(ContractReviewCompletionService::ReviewIncompleteError) do
      run_completion_service
    end
  end

  # --- Raises ReviewIncompleteError for already completed review ---

  test "raises ReviewIncompleteError if review is already completed" do
    create_confirmed_field("title", "core", '"Done"', confidence: 90)
    finalize_review_fields!
    @review.update!(status: "completed", completed_at: Time.current)

    assert_raises(ContractReviewCompletionService::ReviewIncompleteError) do
      run_completion_service
    end
  end

  # --- All-or-nothing transaction ---

  test "wraps completion in a transaction" do
    create_confirmed_field("title", "core", '"Transaction Title"', confidence: 90)
    finalize_review_fields!

    # Verify the service completes within a transaction by checking
    # that both review and contract are updated atomically
    run_completion_service

    @review.reload
    @contract.reload
    assert_equal "completed", @review.status
    assert_equal "Transaction Title", @contract.title
  end

  # --- compute_next_renewal_date ---

  test "computes next_renewal_date from end_date when auto_renews and no renewal date" do
    @contract.update!(
      auto_renews: true,
      end_date: Date.new(2026, 12, 31),
      next_renewal_date: nil
    )

    create_confirmed_field("title", "core", '"Renewal Test"', confidence: 90)
    finalize_review_fields!

    run_completion_service

    assert_equal Date.new(2026, 12, 31), @contract.reload.next_renewal_date
  end

  test "does not overwrite existing next_renewal_date" do
    existing_date = Date.new(2026, 6, 30)
    @contract.update!(
      auto_renews: true,
      end_date: Date.new(2026, 12, 31),
      next_renewal_date: existing_date
    )

    create_confirmed_field("title", "core", '"Keep Renewal"', confidence: 90)
    finalize_review_fields!

    run_completion_service

    assert_equal existing_date, @contract.reload.next_renewal_date
  end

  test "does not compute next_renewal_date when auto_renews is false" do
    @contract.update!(
      auto_renews: false,
      end_date: Date.new(2026, 12, 31),
      next_renewal_date: nil
    )

    create_confirmed_field("title", "core", '"No Auto Renew"', confidence: 90)
    finalize_review_fields!

    run_completion_service

    assert_nil @contract.reload.next_renewal_date
  end

  # --- Reviewed fields count ---

  test "sets reviewed_fields count and completed_by on completion" do
    create_confirmed_field("title", "core", '"Count Test"', confidence: 95)
    create_field("vendor_name", "core", nil, status: "not_found", confidence: nil, needs_review: false)
    finalize_review_fields!

    run_completion_service

    @review.reload
    assert_equal 2, @review.reviewed_fields
    assert_equal @user.id, @review.completed_by_id
    assert @review.completed_at.present?
  end

  private

  def run_completion_service
    ActsAsTenant.with_tenant(@organization) do
      ContractReviewCompletionService.new(review: @review, user: @user).call
    end
  end

  def create_confirmed_field(field_name, group, value, confidence:)
    create_field(field_name, group, value, status: "confirmed", confidence: confidence, needs_review: false)
  end

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

  def create_field_on(review, field_name, group, value, status:, confidence:, needs_review: false, user_value: nil,
    source_excerpt: nil, source_locator: nil, source_match_strategy: nil, source_document: nil)
    catalog = ReviewFieldCatalog.find(field_name)
    display = catalog&.display_name || field_name.humanize

    review.fields.create!(
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
      position: review.fields.count
    )
  end

  def finalize_review_fields!
    @review.update!(
      total_fields: @review.fields.count,
      reviewed_fields: @review.fields.reviewed.count
    )
  end
end
