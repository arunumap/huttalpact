# Implements PRD Section 7 composite readiness model.
#
# Accepts a review-field payload hash and returns { bucket:, reasons: }.
# The orchestration service calls this instead of inline bucketing.
#
# Thresholds use 0-100 integer scale (PRD uses 0.0-1.0 notation):
#   alert-driving:  High >= 95, Review 80-94, Blocked < 80
#   alert-governing: High >= 90, Review 75-89, Blocked < 75
#   contextual:     High >= 85, Review 70-84, never blocks
class FieldReadinessPolicy
  Result = Struct.new(:bucket, :reasons, keyword_init: true)

  # PRD Section 7.5 — thresholds by classification (0-100 integer scale)
  THRESHOLDS = {
    "alert_driving" =>  { high: 95, review: 80 },
    "alert_governing" => { high: 90, review: 75 },
    "contextual" =>     { high: 85, review: 70 }
  }.freeze

  # PRD Section 7.5.2 — field-specific overrides
  FIELD_OVERRIDES = {
    "contract.end_date" => {
      classification_override: "alert_driving",
      extra_high_checks: :end_date_extra_checks
    },
    "contract.auto_renews" => {
      classification_override: "alert_governing",
      extra_high_checks: :auto_renews_extra_checks
    },
    "lease_detail.percentage_rent_report_date" => {
      classification_override: "contextual"
    }
  }.freeze

  BUCKET_ORDER = { "blocked" => 0, "needs_review" => 1, "looks_good" => 2 }.freeze

  # Returns true if the field should be skipped entirely during orchestration.
  # Conditional applicability for direct fields that depend on sibling values.
  def self.applicable?(payload, sibling_payloads:)
    payload = payload.to_h.deep_stringify_keys

    case payload["field_key"]
    when "lease_milestone.recurrence_interval"
      recurring_payload = sibling_payloads_for_index(sibling_payloads, "lease_milestone.recurring", payload["field_index"])
      recurring_payload.present? && truthy?(recurring_payload["value"])
    else
      true
    end
  end

  def self.sibling_payloads_for_index(sibling_payloads, field_key, field_index)
    siblings = sibling_payloads[field_key]
    return nil if siblings.blank?

    siblings.find { |s| s["field_index"] == field_index } || siblings.first
  end

  def self.truthy?(value)
    value == true || value == "true"
  end

  def call(payload, context: {})
    @payload = payload.to_h.deep_stringify_keys
    @context = context.to_h.deep_stringify_keys
    @reasons = []

    bucket = compute_bucket
    Result.new(bucket: bucket, reasons: @reasons.uniq)
  end

  private

  def compute_bucket
    return "looks_good" if app_managed?

    # Derived fields may be "not applicable" based on Section 8 rules.
    # Short-circuit before confidence/structural checks.
    if derived?
      applicability = check_derived_applicability
      return applicability if applicability
    end

    confidence_bucket = confidence_readiness
    structural_bucket = structural_readiness

    # Composite: take the worse of confidence and structural
    worst_bucket(confidence_bucket, structural_bucket)
  end

  # --- Confidence readiness (PRD 7.5) ---

  def confidence_readiness
    score = effective_confidence_score

    if score.nil?
      # Derived fields inherit readiness from dependencies, not their own confidence
      return "looks_good" if derived?
      @reasons << "no_confidence_score"
      # Gating fields with no score must block — treat as confidence 0.
      # Non-gating fields just need a look from the user.
      return gates_activation? ? "blocked" : "needs_review"
    end

    thresholds = thresholds_for_field
    return "looks_good" if thresholds.nil? # app_managed has no thresholds

    if score >= thresholds[:high]
      "looks_good"
    elsif score >= thresholds[:review]
      @reasons << "confidence_below_high_threshold"
      "needs_review"
    else
      @reasons << "confidence_below_review_threshold"
      contextual? ? "needs_review" : "blocked"
    end
  end

  # --- Structural readiness (PRD 7.2) ---

  def structural_readiness
    caps = []

    caps << check_value_presence
    caps << check_conflict
    caps << check_precedence
    caps << check_source_quality
    caps << check_derived_dependencies if derived?
    caps << check_field_specific_high_rules

    caps.compact.min_by { |b| BUCKET_ORDER.fetch(b, 2) }  || "looks_good"
  end

  def check_value_presence
    # false is a valid value (e.g., auto_renews=false); only nil/empty-string counts as missing
    return nil unless value.nil? || (value.is_a?(String) && value.blank?)

    @reasons << "missing_value"
    gates_activation? ? "blocked" : "needs_review"
  end

  def check_conflict
    return nil unless @payload["conflict_candidate"]

    @reasons << "conflict_unresolved"
    gates_activation? ? "blocked" : "needs_review"
  end

  def check_precedence
    return nil unless @payload["supersedes_prior_value"]

    precedence = @payload["precedence_hint"].to_s
    # Unresolved precedence: when a later document supersedes but hint isn't
    # "direct_extraction" (i.e., it's an amendment/addendum override)
    return nil if precedence == "direct_extraction"
    return nil if precedence == "unchanged_from_prior_extraction"

    @reasons << "precedence_unresolved"
    gates_activation? ? "blocked" : "needs_review"
  end

  def check_source_quality
    quality = @payload["source_quality"].to_s

    case quality
    when "poor"
      @reasons << "source_quality_poor"
      gates_activation? ? "blocked" : "needs_review"
    when "warning"
      @reasons << "source_quality_warning"
      "needs_review"
    else
      nil
    end
  end

  # Checks Section 8 derived-value applicability rules.
  # Returns "looks_good" if the field is not applicable; nil otherwise.
  def check_derived_applicability
    check_derived_specific_rules
  end

  def check_derived_dependencies
    dependency_payloads = @context["dependency_payloads"] || {}
    input_keys = Array(@payload["derived_input_keys"])

    return nil if input_keys.empty?

    missing = input_keys.any? do |dep_key|
      deps = dependency_payloads[dep_key]
      next true if deps.blank?
      next false if deps.any? { |d| d["value"].present? }

      # If value is blank, check if the dependency is itself a not-applicable derived field.
      # A not-applicable dependency with nil value should not count as "missing."
      !dependency_not_applicable?(dep_key, dependency_payloads)
    end

    if missing
      @reasons << "derived_dependency_missing"
      return "blocked"
    end

    nil
  end

  def dependency_not_applicable?(dep_key, dep_payloads)
    dep_payload = dep_payloads[dep_key]&.first
    return false unless dep_payload

    dep_result = self.class.new.call(dep_payload, context: { "dependency_payloads" => dep_payloads })
    dep_result.bucket == "looks_good" && dep_result.reasons.any? { |r| r.end_with?("_not_applicable") }
  end

  # PRD Section 8 — named rules for each derived value
  def check_derived_specific_rules
    case @payload["field_key"]
    when "contract.next_renewal_date_fallback"
      check_renewal_fallback_rules
    when "cam_reconciliation_alert_date"
      check_cam_reconciliation_rules
    when "recurring_milestone_next_occurrence_date"
      check_recurring_milestone_rules
    when "notice_period_start_date"
      check_notice_period_rules
    end
  end

  def check_renewal_fallback_rules
    dep_payloads = @context["dependency_payloads"] || {}
    auto_renews_deps = dep_payloads["contract.auto_renews"]
    auto_renews_val = auto_renews_deps&.first&.dig("value")

    unless auto_renews_val == true || auto_renews_val == "true"
      @reasons << "fallback_not_applicable"
      return "looks_good"
    end

    # Fallback only needed when next_renewal_date is blank
    renewal_date_payloads = dep_payloads["contract.next_renewal_date"]
    if renewal_date_payloads.present? && renewal_date_payloads.any? { |p| p["value"].present? }
      @reasons << "fallback_not_applicable"
      return "looks_good"
    end

    nil
  end

  def check_cam_reconciliation_rules
    dep_payloads = @context["dependency_payloads"] || {}
    contract_type_deps = dep_payloads["contract.contract_type"]
    contract_type_val = contract_type_deps&.first&.dig("value").to_s

    unless contract_type_val == "lease"
      @reasons << "cam_not_applicable_for_contract_type"
      return "looks_good"
    end

    nil
  end

  def check_recurring_milestone_rules
    dep_payloads = @context["dependency_payloads"] || {}
    recurring_deps = dep_payloads["lease_milestone.recurring"]
    recurring_val = recurring_deps&.first&.dig("value")

    unless recurring_val == true || recurring_val == "true"
      @reasons << "recurrence_not_applicable"
      return "looks_good"
    end

    nil
  end

  def check_notice_period_rules
    # Ready only if source fields are resolved and non-conflicting.
    # Dependency presence is already checked; no extra structural rule beyond that.
    nil
  end

  # PRD Section 7.5.2 — field-specific High-bucket extra checks
  def check_field_specific_high_rules
    override = FIELD_OVERRIDES[@payload["field_key"]]
    return nil unless override
    return nil unless override[:extra_high_checks]

    send(override[:extra_high_checks])
  end

  def end_date_extra_checks
    # High requires explicit date in source text + acceptable source quality +
    # no unresolved amendment conflict.
    # If source_excerpt is blank, the LLM didn't cite an explicit date.
    if @payload["source_excerpt"].blank? && effective_confidence_score.to_i >= 95
      @reasons << "end_date_no_source_excerpt"
      return "needs_review"
    end

    nil
  end

  def auto_renews_extra_checks
    # High requires a clearly identified renewal clause.
    if @payload["source_excerpt"].blank? && effective_confidence_score.to_i >= 90
      @reasons << "auto_renews_no_source_excerpt"
      return "needs_review"
    end

    nil
  end

  # --- Helpers ---

  def effective_confidence_score
    @payload["confidence_score"]
  end

  def classification
    override = FIELD_OVERRIDES[@payload["field_key"]]
    override&.dig(:classification_override) || @payload["classification"]
  end

  def thresholds_for_field
    THRESHOLDS[classification]
  end

  def value
    @payload["value"]
  end

  def gates_activation?
    !!@payload["gates_activation"]
  end

  def app_managed?
    @payload["source_type"] == "app_managed"
  end

  def derived?
    @payload["source_type"] == "derived"
  end

  def contextual?
    classification == "contextual"
  end

  def worst_bucket(a, b)
    return a if b.nil?
    return b if a.nil?

    BUCKET_ORDER.fetch(a, 2) <= BUCKET_ORDER.fetch(b, 2) ? a : b
  end
end
