require "test_helper"

class FieldReadinessPolicyTest < ActiveSupport::TestCase
  # --- Alert-driving field thresholds (PRD 7.5) ---

  test "alert-driving field with score >= 95 and no structural issues → looks_good" do
    result = evaluate(alert_driving_payload(confidence_score: 95))
    assert_equal "looks_good", result.bucket
    assert_empty result.reasons
  end

  test "alert-driving field with score 94 → needs_review" do
    result = evaluate(alert_driving_payload(confidence_score: 94))
    assert_equal "needs_review", result.bucket
    assert_includes result.reasons, "confidence_below_high_threshold"
  end

  test "alert-driving field with score 80 → needs_review" do
    result = evaluate(alert_driving_payload(confidence_score: 80))
    assert_equal "needs_review", result.bucket
  end

  test "alert-driving field with score 79 → blocked (gating)" do
    result = evaluate(alert_driving_payload(confidence_score: 79))
    assert_equal "blocked", result.bucket
    assert_includes result.reasons, "confidence_below_review_threshold"
  end

  # --- Alert-governing field thresholds ---

  test "alert-governing field with score >= 90 → looks_good" do
    result = evaluate(alert_governing_payload(confidence_score: 90))
    assert_equal "looks_good", result.bucket
  end

  test "alert-governing field with score 89 → needs_review" do
    result = evaluate(alert_governing_payload(confidence_score: 89))
    assert_equal "needs_review", result.bucket
  end

  test "alert-governing field with score 74 → blocked" do
    result = evaluate(alert_governing_payload(confidence_score: 74))
    assert_equal "blocked", result.bucket
  end

  # --- Contextual field thresholds ---

  test "contextual field with score >= 85 → looks_good" do
    result = evaluate(contextual_payload(confidence_score: 85))
    assert_equal "looks_good", result.bucket
  end

  test "contextual field with score 84 → needs_review" do
    result = evaluate(contextual_payload(confidence_score: 84))
    assert_equal "needs_review", result.bucket
  end

  test "contextual field with score 69 → needs_review (never blocks)" do
    result = evaluate(contextual_payload(confidence_score: 69))
    assert_equal "needs_review", result.bucket
    refute_equal "blocked", result.bucket
  end

  # --- App-managed field ---

  test "app-managed field always → looks_good" do
    payload = base_payload.merge(
      "source_type" => "app_managed",
      "classification" => "app_managed",
      "confidence_score" => nil,
      "gates_activation" => false
    )
    result = evaluate(payload)
    assert_equal "looks_good", result.bucket
  end

  # --- Structural checks ---

  test "missing value on gating field → blocked" do
    result = evaluate(alert_driving_payload(value: nil, confidence_score: 95))
    assert_equal "blocked", result.bucket
    assert_includes result.reasons, "missing_value"
  end

  test "missing value on non-gating field → needs_review" do
    result = evaluate(contextual_payload(value: nil, confidence_score: 95))
    assert_equal "needs_review", result.bucket
    assert_includes result.reasons, "missing_value"
  end

  test "false value is not treated as missing" do
    result = evaluate(alert_governing_payload(value: false, confidence_score: 97))
    assert_equal "looks_good", result.bucket
    refute_includes result.reasons, "missing_value"
  end

  test "empty string value is treated as missing" do
    result = evaluate(alert_driving_payload(value: "", confidence_score: 95))
    assert_includes result.reasons, "missing_value"
  end

  test "conflict candidate on gating field → blocked" do
    result = evaluate(alert_driving_payload(confidence_score: 95, conflict_candidate: true))
    assert_equal "blocked", result.bucket
    assert_includes result.reasons, "conflict_unresolved"
  end

  test "conflict candidate on non-gating field → needs_review" do
    result = evaluate(contextual_payload(confidence_score: 95, conflict_candidate: true))
    assert_equal "needs_review", result.bucket
    assert_includes result.reasons, "conflict_unresolved"
  end

  test "poor source quality on gating field → blocked" do
    result = evaluate(alert_driving_payload(confidence_score: 95, source_quality: "poor"))
    assert_equal "blocked", result.bucket
    assert_includes result.reasons, "source_quality_poor"
  end

  test "warning source quality → needs_review" do
    result = evaluate(alert_driving_payload(confidence_score: 95, source_quality: "warning"))
    assert_equal "needs_review", result.bucket
    assert_includes result.reasons, "source_quality_warning"
  end

  test "unresolved precedence on gating field → blocked" do
    payload = alert_driving_payload(confidence_score: 95).merge(
      "supersedes_prior_value" => true,
      "precedence_hint" => "later_addendum_overrides_prior_terms"
    )
    result = evaluate(payload)
    assert_equal "blocked", result.bucket
    assert_includes result.reasons, "precedence_unresolved"
  end

  test "direct_extraction precedence does not trigger precedence check" do
    payload = alert_driving_payload(confidence_score: 95).merge(
      "supersedes_prior_value" => true,
      "precedence_hint" => "direct_extraction"
    )
    result = evaluate(payload)
    assert_equal "looks_good", result.bucket
  end

  # --- Derived field behavior ---

  test "derived field with missing dependency → blocked" do
    payload = derived_payload(confidence_score: nil).merge(
      "derived_input_keys" => [ "contract.notice_period_days" ]
    )
    context = { "dependency_payloads" => {
      "contract.notice_period_days" => [ { "value" => nil } ]
    } }
    result = evaluate(payload, context: context)
    assert_equal "blocked", result.bucket
    assert_includes result.reasons, "derived_dependency_missing"
  end

  test "derived field with present dependencies and no confidence → looks_good (inherits)" do
    payload = derived_payload(confidence_score: nil).merge(
      "derived_input_keys" => [ "contract.end_date" ]
    )
    context = { "dependency_payloads" => {
      "contract.end_date" => [ { "value" => "2030-12-31" } ]
    } }
    result = evaluate(payload, context: context)
    assert_equal "looks_good", result.bucket
  end

  # --- No confidence score ---

  test "gating field with nil confidence → blocked (treat as confidence 0)" do
    result = evaluate(alert_driving_payload(confidence_score: nil))
    assert_equal "blocked", result.bucket
    assert_includes result.reasons, "no_confidence_score"
  end

  test "non-gating field with nil confidence → needs_review" do
    result = evaluate(contextual_payload(confidence_score: nil))
    assert_equal "needs_review", result.bucket
    assert_includes result.reasons, "no_confidence_score"
  end

  # --- Composite: worst of confidence + structural ---

  test "high confidence but with conflict → worst wins" do
    result = evaluate(alert_driving_payload(confidence_score: 99, conflict_candidate: true))
    assert_equal "blocked", result.bucket
  end

  test "mid confidence and warning source quality → needs_review (both contribute)" do
    result = evaluate(alert_driving_payload(confidence_score: 90, source_quality: "warning"))
    assert_equal "needs_review", result.bucket
    assert_includes result.reasons, "confidence_below_high_threshold"
    assert_includes result.reasons, "source_quality_warning"
  end

  # --- Section 7.5.2 field-specific rules ---

  test "contract.end_date without source excerpt even at high confidence → needs_review" do
    payload = alert_driving_payload(confidence_score: 96).merge(
      "field_key" => "contract.end_date",
      "source_excerpt" => nil
    )
    result = evaluate(payload)
    assert_equal "needs_review", result.bucket
    assert_includes result.reasons, "end_date_no_source_excerpt"
  end

  test "contract.end_date with source excerpt and high confidence → looks_good" do
    payload = alert_driving_payload(confidence_score: 96).merge(
      "field_key" => "contract.end_date",
      "source_excerpt" => "Lease expires December 31, 2030"
    )
    result = evaluate(payload)
    assert_equal "looks_good", result.bucket
  end

  test "contract.auto_renews without source excerpt even at high confidence → needs_review" do
    payload = alert_governing_payload(confidence_score: 92).merge(
      "field_key" => "contract.auto_renews",
      "source_excerpt" => nil
    )
    result = evaluate(payload)
    assert_equal "needs_review", result.bucket
    assert_includes result.reasons, "auto_renews_no_source_excerpt"
  end

  # --- Section 8 derived-value rules ---

  test "renewal fallback with auto_renews=false → looks_good (not applicable)" do
    payload = derived_payload.merge(
      "field_key" => "contract.next_renewal_date_fallback",
      "derived_input_keys" => %w[contract.auto_renews contract.end_date]
    )
    context = { "dependency_payloads" => {
      "contract.auto_renews" => [ { "value" => false } ],
      "contract.end_date" => [ { "value" => "2030-12-31" } ]
    } }
    result = evaluate(payload, context: context)
    assert_equal "looks_good", result.bucket
    assert_includes result.reasons, "fallback_not_applicable"
  end

  test "renewal fallback with auto_renews=true and next_renewal_date present → looks_good (not applicable)" do
    payload = derived_payload.merge(
      "field_key" => "contract.next_renewal_date_fallback",
      "derived_input_keys" => %w[contract.auto_renews contract.end_date]
    )
    context = { "dependency_payloads" => {
      "contract.auto_renews" => [ { "value" => true } ],
      "contract.end_date" => [ { "value" => "2030-12-31" } ],
      "contract.next_renewal_date" => [ { "value" => "2031-01-01" } ]
    } }
    result = evaluate(payload, context: context)
    assert_equal "looks_good", result.bucket
    assert_includes result.reasons, "fallback_not_applicable"
  end

  test "recurring_milestone_next_occurrence_date with recurring=false → looks_good" do
    payload = derived_payload.merge(
      "field_key" => "recurring_milestone_next_occurrence_date",
      "derived_input_keys" => %w[lease_milestone.due_date lease_milestone.recurring lease_milestone.recurrence_interval]
    )
    context = { "dependency_payloads" => {
      "lease_milestone.due_date" => [ { "value" => "2030-06-15" } ],
      "lease_milestone.recurring" => [ { "value" => false } ],
      "lease_milestone.recurrence_interval" => [ { "value" => nil } ]
    } }
    result = evaluate(payload, context: context)
    assert_equal "looks_good", result.bucket
    assert_includes result.reasons, "recurrence_not_applicable"
  end

  test "cam_reconciliation_alert_date with non-lease contract → looks_good" do
    payload = derived_payload.merge(
      "field_key" => "cam_reconciliation_alert_date",
      "derived_input_keys" => %w[contract.contract_type lease_detail.cam_reconciliation_month]
    )
    context = { "dependency_payloads" => {
      "contract.contract_type" => [ { "value" => "service_agreement" } ],
      "lease_detail.cam_reconciliation_month" => [ { "value" => "March" } ]
    } }
    result = evaluate(payload, context: context)
    assert_equal "looks_good", result.bucket
    assert_includes result.reasons, "cam_not_applicable_for_contract_type"
  end

  # --- Applicability class method ---

  test "recurrence_interval is not applicable when recurring=false for same index" do
    interval_payload = base_payload.merge(
      "field_key" => "lease_milestone.recurrence_interval",
      "field_index" => 0,
      "value" => nil
    )
    sibling_payloads = {
      "lease_milestone.recurring" => [ { "field_key" => "lease_milestone.recurring", "field_index" => 0, "value" => false } ]
    }
    refute FieldReadinessPolicy.applicable?(interval_payload, sibling_payloads: sibling_payloads)
  end

  test "recurrence_interval is applicable when recurring=true for same index" do
    interval_payload = base_payload.merge(
      "field_key" => "lease_milestone.recurrence_interval",
      "field_index" => 0,
      "value" => "annual"
    )
    sibling_payloads = {
      "lease_milestone.recurring" => [ { "field_key" => "lease_milestone.recurring", "field_index" => 0, "value" => true } ]
    }
    assert FieldReadinessPolicy.applicable?(interval_payload, sibling_payloads: sibling_payloads)
  end

  test "non-conditional fields are always applicable" do
    assert FieldReadinessPolicy.applicable?(alert_driving_payload, sibling_payloads: {})
  end

  private

  def evaluate(payload, context: {})
    FieldReadinessPolicy.new.call(payload, context: context)
  end

  def base_payload
    {
      "field_key" => "contract.end_date",
      "value" => "2030-12-31",
      "confidence_score" => 95,
      "source_type" => "direct",
      "classification" => "alert_driving",
      "field_family" => "alert_date",
      "gates_activation" => true,
      "conflict_candidate" => false,
      "source_quality" => "good",
      "source_excerpt" => "Supporting text",
      "precedence_hint" => "direct_extraction",
      "supersedes_prior_value" => false,
      "derived_input_keys" => []
    }
  end

  def alert_driving_payload(confidence_score: 95, value: "2030-12-31", conflict_candidate: false, source_quality: "good")
    base_payload.merge(
      "confidence_score" => confidence_score,
      "value" => value,
      "conflict_candidate" => conflict_candidate,
      "source_quality" => source_quality
    )
  end

  def alert_governing_payload(confidence_score: 90, value: true, conflict_candidate: false, source_quality: "good")
    base_payload.merge(
      "field_key" => "contract.auto_renews",
      "classification" => "alert_governing",
      "field_family" => "alert_governing_boolean",
      "confidence_score" => confidence_score,
      "value" => value,
      "conflict_candidate" => conflict_candidate,
      "source_quality" => source_quality,
      "source_excerpt" => "This lease shall automatically renew"
    )
  end

  def contextual_payload(confidence_score: 85, value: "2030-03-31", conflict_candidate: false, source_quality: "good")
    base_payload.merge(
      "field_key" => "lease_detail.percentage_rent_report_date",
      "classification" => "contextual",
      "field_family" => "contextual_date",
      "gates_activation" => false,
      "confidence_score" => confidence_score,
      "value" => value,
      "conflict_candidate" => conflict_candidate,
      "source_quality" => source_quality
    )
  end

  def derived_payload(confidence_score: nil, value: "2030-06-01")
    base_payload.merge(
      "field_key" => "notice_period_start_date",
      "classification" => "alert_driving",
      "field_family" => "derived_date",
      "source_type" => "derived",
      "confidence_score" => confidence_score,
      "value" => value,
      "derived_input_keys" => %w[contract.notice_period_days contract.next_renewal_date contract.end_date contract.next_renewal_date_fallback]
    )
  end
end
