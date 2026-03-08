require "test_helper"

class ContractReviewOrchestrationServiceTest < ActiveSupport::TestCase
  setup do
    @organization = organizations(:one)
    @lease_contract = contracts(:commercial_lease)
    @lease_document = @lease_contract.contract_documents.create!(
      extraction_status: "completed",
      extracted_text: "Commercial lease text",
      document_type: "main_contract",
      position: 0,
      file: Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/test.txt"), "text/plain")
    )
  end

  test "full extraction creates review records, summary counts, and transitions contract into review" do
    create_ai_usage_log(@lease_contract)

    review = ContractReviewOrchestrationService.new(
      @lease_contract,
      extraction_result: {
        "review_fields" => [
          review_field_payload("contract.end_date", value: "2030-12-31", source_document: @lease_document.filename),
          review_field_payload("contract.contract_type", value: "lease", source_document: @lease_document.filename),
          review_field_payload("lease_detail.percentage_rent_report_date", value: "2030-03-31", source_document: @lease_document.filename),
          review_field_payload("contract.status", value: "active", current_canonical_value: "active")
        ],
        "changed_field_keys" => %w[contract.end_date contract.contract_type lease_detail.percentage_rent_report_date],
        "impacted_field_keys" => %w[contract.end_date contract.contract_type lease_detail.percentage_rent_report_date]
      },
      mode: :full
    ).call

    @lease_contract.reload

    assert_equal "in_review", @lease_contract.status
    assert_equal 4, review.total_fields_count
    # Under Section 7 composite readiness: high-confidence, no-conflict fields → looks_good
    assert_equal 4, review.looks_good_fields_count
    assert_equal 0, review.needs_review_fields_count
    assert_equal 0, review.blocked_fields_count
  end

  test "full extraction promotes draft contracts into review" do
    draft = Contract.create!(
      title: "Untitled Draft",
      status: "draft",
      organization: @organization,
      uploaded_by: users(:one)
    )
    document = draft.contract_documents.create!(
      extraction_status: "completed",
      extracted_text: "Draft contract text",
      document_type: "main_contract",
      position: 0,
      file: Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/test.txt"), "text/plain")
    )
    create_ai_usage_log(draft)

    ContractReviewOrchestrationService.new(
      draft,
      extraction_result: {
        "review_fields" => [
          review_field_payload("contract.end_date", value: "2030-12-31", source_document: document.filename)
        ],
        "changed_field_keys" => [ "contract.end_date" ],
        "impacted_field_keys" => [ "contract.end_date" ]
      },
      mode: :full
    ).call

    assert_equal "in_review", draft.reload.status
  end

  test "incremental addendum preserves approved context and reopens only impacted fields" do
    contract = contracts(:hvac_maintenance)
    existing_alert = contract.alerts.create!(
      organization: contract.organization,
      alert_type: "expiry_warning",
      trigger_date: 30.days.from_now.to_date,
      status: "pending",
      message: "Contract expiry approaching"
    )
    new_document = contract.contract_documents.create!(
      extraction_status: "completed",
      extracted_text: "Addendum extends the contract term.",
      document_type: "addendum",
      position: 1,
      file: Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/test.txt"), "text/plain")
    )

    previous_review = ActsAsTenant.with_tenant(contract.organization) do
      review = contract.contract_reviews.create!(organization: contract.organization, status: "completed", review_trigger: "initial_extraction")
      review.contract_review_fields.create!(
        contract:,
        organization: contract.organization,
        field_key: "contract.end_date",
        extracted_value: "2026-12-31",
        approved_value: "2026-12-31",
        readiness_bucket: "looks_good",
        review_status: "confirmed",
        reviewed_by: users(:one),
        reviewed_at: Time.current
      )
      review.contract_review_fields.create!(
        contract:,
        organization: contract.organization,
        field_key: "contract.notice_period_days",
        extracted_value: 30,
        approved_value: 30,
        readiness_bucket: "looks_good",
        review_status: "confirmed",
        reviewed_by: users(:one),
        reviewed_at: Time.current
      )
      review
    end

    review = ContractReviewOrchestrationService.new(
      contract,
      extraction_result: {
        "review_fields" => [
          review_field_payload(
            "contract.end_date",
            value: "2027-06-30",
            current_canonical_value: "2026-12-31",
            source_document: new_document.filename,
            conflict_candidate: true,
            conflict_candidate_reason: "Addendum proposes a later end date.",
            impacted_by_new_document: true
          ),
          review_field_payload(
            "contract.notice_period_days",
            value: 30,
            current_canonical_value: 30,
            source_document: @lease_document.filename,
            impacted_by_new_document: false
          ),
          review_field_payload("contract.status", value: "active", current_canonical_value: "active")
        ],
        "changed_field_keys" => [ "contract.end_date" ],
        "impacted_field_keys" => [ "contract.end_date" ]
      },
      mode: :incremental
    ).call

    contract.reload
    end_date_field = review.contract_review_fields.find_by!(field_key: "contract.end_date")
    notice_field = review.contract_review_fields.find_by!(field_key: "contract.notice_period_days")

    assert_equal "completed", previous_review.reload.status
    assert_equal "in_review", contract.status
    assert_equal "pending", end_date_field.review_status
    assert_equal "blocked", end_date_field.readiness_bucket
    assert_equal "confirmed", notice_field.review_status
    assert_equal 30, notice_field.approved_value
    assert_equal "looks_good", notice_field.readiness_bucket
    assert_equal 1, review.contract_review_conflicts.count
    assert_includes contract.alerts.ids, existing_alert.id
    assert_equal "pending", existing_alert.reload.status
    assert_includes end_date_field.contract_review_field_events.pluck(:action), "reopened"
  end

  test "derived dependency gaps create blocking conflicts" do
    review = ContractReviewOrchestrationService.new(
      @lease_contract,
      extraction_result: {
        "review_fields" => [
          review_field_payload("contract.end_date", value: "2030-12-31", source_document: @lease_document.filename),
          review_field_payload("contract.notice_period_days", value: nil, current_canonical_value: nil, source_document: @lease_document.filename),
          review_field_payload(
            "notice_period_start_date",
            value: nil,
            current_canonical_value: nil,
            source_document: @lease_document.filename
          )
        ],
        "changed_field_keys" => %w[contract.end_date contract.notice_period_days notice_period_start_date],
        "impacted_field_keys" => %w[contract.end_date contract.notice_period_days notice_period_start_date]
      },
      mode: :full
    ).call

    derived_field = review.contract_review_fields.find_by!(field_key: "notice_period_start_date")
    conflict = derived_field.contract_review_conflicts.first

    assert_equal "blocked", derived_field.readiness_bucket
    assert_equal "derived_dependency_missing", conflict.conflict_type
    assert conflict.blocks_activation?
  end

  test "locks the contract while creating a review" do
    locked = false

    @lease_contract.stub(:with_lock, ->(*_args, &block) {
      locked = true
      block.call
    }) do
      ContractReviewOrchestrationService.new(
        @lease_contract,
        extraction_result: {
          "review_fields" => [
            review_field_payload("contract.end_date", value: "2030-12-31", source_document: @lease_document.filename)
          ],
          "changed_field_keys" => [ "contract.end_date" ],
          "impacted_field_keys" => [ "contract.end_date" ]
        },
        mode: :full
      ).call
    end

    assert locked, "Expected the contract row to be locked during review orchestration"
  end

  # --- Section 7 regression: ClearPath-shaped simple lease ---

  test "ClearPath-shaped simple lease produces exception-first review, not 44 blockers" do
    create_ai_usage_log(@lease_contract)

    review = ContractReviewOrchestrationService.new(
      @lease_contract,
      extraction_result: clearpath_extraction_result,
      mode: :full
    ).call

    fields = review.contract_review_fields.where.not(source_type: "app_managed")
    blocked = fields.where(readiness_bucket: "blocked")
    needs_review = fields.where(readiness_bucket: "needs_review")
    looks_good = fields.where(readiness_bucket: "looks_good")

    # High-confidence, no-conflict fields should NOT be blocked
    assert blocked.count < 10, "Expected fewer than 10 blockers for a simple lease, got #{blocked.count}"
    assert looks_good.count > 0, "Expected some looks_good fields"

    # Specific: high-confidence direct dates should be looks_good
    end_date = fields.find_by(field_key: "contract.end_date")
    assert_equal "looks_good", end_date.readiness_bucket

    # Contextual fields never block
    pct_rent = fields.find_by(field_key: "lease_detail.percentage_rent_report_date")
    refute_equal "blocked", pct_rent.readiness_bucket if pct_rent

    # Non-recurring milestones: recurrence_interval should be skipped
    interval_fields = fields.where(field_key: "lease_milestone.recurrence_interval")
    assert_equal 0, interval_fields.count, "Non-recurring milestones should not have recurrence_interval fields"

    # Derived fields with met dependencies should not be blocked
    notice_start = fields.find_by(field_key: "notice_period_start_date")
    assert_equal "looks_good", notice_start.readiness_bucket if notice_start
  end

  test "readiness_reasons and confidence_score are persisted after orchestration" do
    create_ai_usage_log(@lease_contract)

    review = ContractReviewOrchestrationService.new(
      @lease_contract,
      extraction_result: {
        "review_fields" => [
          review_field_payload("contract.end_date", value: "2030-12-31", source_document: @lease_document.filename, confidence_score: 82),
          review_field_payload("contract.contract_type", value: "lease", source_document: @lease_document.filename, confidence_score: 95)
        ],
        "changed_field_keys" => %w[contract.end_date contract.contract_type],
        "impacted_field_keys" => %w[contract.end_date contract.contract_type]
      },
      mode: :full
    ).call

    end_date = review.contract_review_fields.find_by(field_key: "contract.end_date")
    assert_equal 82, end_date.confidence_score
    assert_equal "needs_review", end_date.readiness_bucket
    assert_includes end_date.readiness_reasons, "confidence_below_high_threshold"

    contract_type = review.contract_review_fields.find_by(field_key: "contract.contract_type")
    assert_equal 95, contract_type.confidence_score
    assert_equal "looks_good", contract_type.readiness_bucket
  end

  test "non-applicable recurrence_interval fields are skipped in orchestration" do
    create_ai_usage_log(@lease_contract)

    review = ContractReviewOrchestrationService.new(
      @lease_contract,
      extraction_result: {
        "review_fields" => [
          review_field_payload("lease_milestone.due_date", value: "2030-06-01", source_document: @lease_document.filename).merge("field_index" => 0),
          review_field_payload("lease_milestone.recurring", value: false, source_document: @lease_document.filename).merge("field_index" => 0),
          review_field_payload("lease_milestone.recurrence_interval", value: nil, source_document: @lease_document.filename).merge("field_index" => 0)
        ],
        "changed_field_keys" => %w[lease_milestone.due_date lease_milestone.recurring lease_milestone.recurrence_interval],
        "impacted_field_keys" => %w[lease_milestone.due_date lease_milestone.recurring lease_milestone.recurrence_interval]
      },
      mode: :full
    ).call

    interval = review.contract_review_fields.find_by(field_key: "lease_milestone.recurrence_interval")
    assert_nil interval, "recurrence_interval should not be created when recurring=false"
  end

  private

  def clearpath_extraction_result
    doc = @lease_document.filename
    {
      "review_fields" => [
        review_field_payload("contract.end_date", value: "2030-12-31", source_document: doc, confidence_score: 96),
        review_field_payload("contract.next_renewal_date", value: "2031-01-01", source_document: doc, confidence_score: 92),
        review_field_payload("contract.auto_renews", value: true, source_document: doc, confidence_score: 93),
        review_field_payload("contract.notice_period_days", value: 90, source_document: doc, confidence_score: 97),
        review_field_payload("contract.contract_type", value: "lease", source_document: doc, confidence_score: 98),
        review_field_payload("lease_detail.cam_reconciliation_month", value: "March", source_document: doc, confidence_score: 88),
        review_field_payload("lease_detail.ti_deadline", value: "2026-09-01", source_document: doc, confidence_score: 91),
        review_field_payload("lease_detail.percentage_rent_report_date", value: "2026-03-31", source_document: doc, confidence_score: 78),
        # 3 rent escalations
        review_field_payload("rent_escalation.effective_date", value: "2027-01-01", source_document: doc, confidence_score: 95).merge("field_index" => 0),
        review_field_payload("rent_escalation.effective_date", value: "2028-01-01", source_document: doc, confidence_score: 93).merge("field_index" => 1),
        review_field_payload("rent_escalation.effective_date", value: "2029-01-01", source_document: doc, confidence_score: 91).merge("field_index" => 2),
        # 2 lease options
        review_field_payload("lease_option.notice_deadline", value: "2029-06-01", source_document: doc, confidence_score: 94).merge("field_index" => 0),
        review_field_payload("lease_option.exercise_deadline", value: "2029-09-01", source_document: doc, confidence_score: 87).merge("field_index" => 0),
        # 3 milestones (non-recurring)
        review_field_payload("lease_milestone.due_date", value: "2026-06-01", source_document: doc, confidence_score: 96).merge("field_index" => 0),
        review_field_payload("lease_milestone.recurring", value: false, source_document: doc, confidence_score: 95).merge("field_index" => 0),
        review_field_payload("lease_milestone.recurrence_interval", value: nil, source_document: doc, confidence_score: nil).merge("field_index" => 0),
        review_field_payload("lease_milestone.due_date", value: "2027-01-15", source_document: doc, confidence_score: 94).merge("field_index" => 1),
        review_field_payload("lease_milestone.recurring", value: false, source_document: doc, confidence_score: 93).merge("field_index" => 1),
        review_field_payload("lease_milestone.recurrence_interval", value: nil, source_document: doc, confidence_score: nil).merge("field_index" => 1),
        review_field_payload("lease_milestone.due_date", value: "2027-06-01", source_document: doc, confidence_score: 92).merge("field_index" => 2),
        review_field_payload("lease_milestone.recurring", value: false, source_document: doc, confidence_score: 92).merge("field_index" => 2),
        review_field_payload("lease_milestone.recurrence_interval", value: nil, source_document: doc, confidence_score: nil).merge("field_index" => 2),
        # Derived fields
        review_field_payload("notice_period_start_date", value: "2030-10-02", source_document: doc, confidence_score: nil),
        review_field_payload("cam_reconciliation_alert_date", value: "2026-02-15", source_document: doc, confidence_score: nil),
        review_field_payload("contract.next_renewal_date_fallback", value: nil, source_document: doc, confidence_score: nil),
        # Recurring milestone derived (non-recurring milestones)
        review_field_payload("recurring_milestone_next_occurrence_date", value: nil, source_document: doc, confidence_score: nil).merge("field_index" => 0),
        review_field_payload("recurring_milestone_next_occurrence_date", value: nil, source_document: doc, confidence_score: nil).merge("field_index" => 1),
        review_field_payload("recurring_milestone_next_occurrence_date", value: nil, source_document: doc, confidence_score: nil).merge("field_index" => 2),
        # App-managed
        review_field_payload("contract.status", value: "active", current_canonical_value: "active")
      ],
      "changed_field_keys" => %w[
        contract.end_date contract.next_renewal_date contract.auto_renews
        contract.notice_period_days contract.contract_type
        lease_detail.cam_reconciliation_month lease_detail.ti_deadline
        lease_detail.percentage_rent_report_date
        rent_escalation.effective_date lease_option.notice_deadline
        lease_option.exercise_deadline lease_milestone.due_date
        lease_milestone.recurring lease_milestone.recurrence_interval
        notice_period_start_date cam_reconciliation_alert_date
        contract.next_renewal_date_fallback recurring_milestone_next_occurrence_date
      ],
      "impacted_field_keys" => %w[
        contract.end_date contract.next_renewal_date contract.auto_renews
        contract.notice_period_days contract.contract_type
        lease_detail.cam_reconciliation_month lease_detail.ti_deadline
        lease_detail.percentage_rent_report_date
        rent_escalation.effective_date lease_option.notice_deadline
        lease_option.exercise_deadline lease_milestone.due_date
        lease_milestone.recurring lease_milestone.recurrence_interval
        notice_period_start_date cam_reconciliation_alert_date
        contract.next_renewal_date_fallback recurring_milestone_next_occurrence_date
      ]
    }
  end

  def create_ai_usage_log(contract)
    AiUsageLog.create!(
      organization: contract.organization,
      contract:,
      ai_model: "claude-sonnet-4",
      input_tokens: 1500,
      output_tokens: 400,
      extraction_mode: "full"
    )
  end

  def review_field_payload(field_key, value:, source_document: nil, current_canonical_value: nil, conflict_candidate: false, conflict_candidate_reason: nil, impacted_by_new_document: true, confidence_score: 95, source_quality: "good")
    definition = ReviewFieldCatalog.fetch(field_key)

    {
      "field_key" => field_key,
      "field_index" => nil,
      "value" => value,
      "current_canonical_value" => current_canonical_value,
      "source_document" => source_document,
      "source_reference" => "Page 1",
      "source_excerpt" => "Supporting text",
      "precedence_hint" => "direct_extraction",
      "confidence_score" => confidence_score,
      "source_quality" => source_quality,
      "field_family" => definition.field_family,
      "classification" => definition.classification,
      "source_type" => definition.source_type,
      "alert_family_keys" => definition.alert_families,
      "derived_input_keys" => definition.dependencies,
      "gates_activation" => definition.blocks_activation?,
      "impacted_by_new_document" => impacted_by_new_document,
      "conflict_candidate" => conflict_candidate,
      "conflict_candidate_reason" => conflict_candidate_reason
    }
  end
end
