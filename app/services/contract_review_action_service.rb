class ContractReviewActionService
  class ActionError < StandardError; end

  def initialize(review:, user:)
    @review = review
    @user = user
    @contract = review.contract
    @resolver = ContractReviewValueResolver.new(@contract)
  end

  def save_progress!
    raise ActionError, "This review has already been completed." unless @review.open?

    @review.touch
    create_review_audit!("review_progress_saved", "Saved human review progress with #{pending_field_count} pending #{'item'.pluralize(pending_field_count)} remaining.")
  end

  def bulk_confirm_safe_items!
    raise ActionError, "This review has already been completed." unless @review.open?

    eligible_fields = reviewable_fields.where(review_status: "pending", readiness_bucket: "looks_good").where.not(source_type: "app_managed")
    count = 0

    ActiveRecord::Base.transaction do
      eligible_fields.find_each do |field|
        resolve_field!(field, review_status: "confirmed", approved_value: field.extracted_value, note: field.review_note, event_action: "bulk_confirmed", audit_action: nil, recalculate: false)
        count += 1
      end

      recalculate_derived_fields!
      @review.refresh_summary!
      create_review_audit!("review_bulk_confirmed", "Confirmed #{count} safe #{'field'.pluralize(count)} from the review queue.") if count.positive?
    end

    count
  end

  def confirm!(field:, note: nil)
    resolve_field!(field, review_status: "confirmed", approved_value: field.extracted_value, note:, event_action: "confirmed", audit_action: "review_field_confirmed")
  end

  def edit!(field:, raw_value:, note: nil)
    approved_value = @resolver.normalize_input(field:, raw_value:)
    resolve_field!(field, review_status: "edited", approved_value:, note:, event_action: "edited", audit_action: "review_field_edited")
  rescue ArgumentError => e
    raise ActionError, e.message
  end

  def mark_not_found!(field:, note: nil)
    resolve_field!(field, review_status: "not_found", approved_value: nil, note:, event_action: "marked_not_found", audit_action: "review_field_marked_not_found")
  end

  def mark_not_applicable!(field:, note: nil)
    resolve_field!(field, review_status: "not_applicable", approved_value: nil, note:, event_action: "marked_not_applicable", audit_action: "review_field_marked_not_applicable")
  end

  private

  def resolve_field!(field, review_status:, approved_value:, note:, event_action:, audit_action:, recalculate: true)
    ensure_field_editable!(field)

    ActiveRecord::Base.transaction do
      from_status = field.review_status
      from_value = field.effective_value

      field.update!(
        approved_value:,
        review_status:,
        readiness_bucket: "looks_good",
        review_note: note.presence,
        reviewed_by: @user,
        reviewed_at: Time.current
      )

      resolve_conflicts!(field, approved_value:, note:)
      create_field_event!(field, action: event_action, from_status:, from_value:, note:, to_value: field.effective_value)
      recalculate_derived_fields! if recalculate
      @review.refresh_summary!
      create_field_audit!(field, audit_action, review_status:, note:) if audit_action.present?
      field
    end
  end

  def ensure_field_editable!(field)
    raise ActionError, "This review has been superseded by a newer extraction." if @review.superseded?
    raise ActionError, "App-managed review fields cannot be changed manually." if field.source_type == "app_managed"

    if @review.completed? && field.gates_activation?
      raise ActionError, "Activation-driving fields can only be changed while the contract is in review."
    end
  end

  def resolve_conflicts!(field, approved_value:, note:)
    field.contract_review_conflicts.open.find_each do |conflict|
      conflict.update!(
        status: "resolved",
        resolved_by: @user,
        resolved_at: Time.current,
        resolution_value: approved_value,
        resolution_notes: note.presence || default_resolution_note(field),
        approved_value: approved_value
      )

      field.contract_review_field_events.create!(
        contract_review: @review,
        contract: @contract,
        organization: @contract.organization,
        user: @user,
        action: "conflict_resolved",
        from_review_status: field.review_status,
        to_review_status: field.review_status,
        from_value: field.effective_value,
        to_value: field.effective_value,
        metadata: {
          "conflict_id" => conflict.id,
          "conflict_type" => conflict.conflict_type
        },
        note: conflict.resolution_notes
      )
    end
  end

  def create_field_event!(field, action:, from_status:, from_value:, note:, to_value:)
    field.contract_review_field_events.create!(
      contract_review: @review,
      contract: @contract,
      organization: @contract.organization,
      user: @user,
      action:,
      from_review_status: from_status,
      to_review_status: field.review_status,
      from_value:,
      to_value:,
      metadata: {
        "field_key" => field.field_key,
        "field_index" => field.field_index,
        "follow_through" => @review.completed?
      },
      note:
    )
  end

  def recalculate_derived_fields!
    data = review_data_snapshot

    derived_fields.each do |field|
      new_value = @resolver.derived_value(field.field_key, data:, field_index: field.field_index)
      dependencies_ready = dependencies_ready_for?(field)
      from_status = field.review_status
      from_value = field.effective_value

      attributes = if dependencies_ready
        {
          approved_value: new_value,
          review_status: "confirmed",
          readiness_bucket: "looks_good",
          readiness_reasons: [],
          reviewed_at: Time.current,
          reviewed_by: nil
        }
      else
        readiness = rebucket_field(field)
        {
          approved_value: nil,
          review_status: "pending",
          readiness_bucket: readiness.bucket,
          readiness_reasons: readiness.reasons,
          reviewed_at: nil,
          reviewed_by: nil
        }
      end

      field.assign_attributes(attributes)
      next unless field.changed?

      field.save!
      sync_derived_conflicts!(field, dependencies_ready)
      field.contract_review_field_events.create!(
        contract_review: @review,
        contract: @contract,
        organization: @contract.organization,
        user: @user,
        action: "recalculated",
        from_review_status: from_status,
        to_review_status: field.review_status,
        from_value:,
        to_value: field.effective_value,
        metadata: {
          "field_key" => field.field_key,
          "field_index" => field.field_index,
          "dependencies_ready" => dependencies_ready
        },
        note: "Recalculated from approved review dependencies."
      )

      @resolver.assign_value(data:, field_key: field.field_key, value: field.approved_value, field_index: field.field_index) if field.source_type == "direct"
    end
  end

  def review_data_snapshot
    data = @resolver.snapshot.deep_dup

    reviewable_fields.where(source_type: "direct").where.not(review_status: "pending").find_each do |field|
      @resolver.assign_value(data:, field_key: field.field_key, value: field.approved_value, field_index: field.field_index)
    end

    data
  end

  def dependencies_ready_for?(field)
    field.derived_dependency_keys.all? do |dependency_key|
      dependency_field = find_dependency_field(field, dependency_key)
      next true unless dependency_field

      dependency_field.reviewed? || dependency_field.readiness_bucket == "looks_good"
    end
  end

  def find_dependency_field(field, dependency_key)
    scope = reviewable_fields.where(field_key: dependency_key)
    dependency_definition = ReviewFieldCatalog.fetch(dependency_key)

    if dependency_definition.repeatable?
      scope.find_by(field_index: field.field_index)
    else
      scope.find_by(field_index: nil)
    end
  rescue KeyError
    nil
  end

  def sync_derived_conflicts!(field, dependencies_ready)
    open_conflicts = field.contract_review_conflicts.open.where(conflict_type: "derived_dependency_missing")

    if dependencies_ready
      open_conflicts.find_each do |conflict|
        conflict.update!(
          status: "resolved",
          resolved_by: @user,
          resolved_at: Time.current,
          resolution_notes: "Derived dependencies were resolved during review."
        )
      end
      return
    end

    return if open_conflicts.exists?

    field.contract_review_conflicts.create!(
      contract_review: @review,
      contract: @contract,
      organization: @contract.organization,
      conflict_type: "derived_dependency_missing",
      blocks_activation: field.gates_activation,
      status: "open",
      summary: "Derived dependencies are incomplete for #{field.field_key}.",
      details: "Approve or invalidate the dependency fields before completing review.",
      extracted_value: field.extracted_value,
      approved_value: field.approved_value,
      source_span: field.source_span
    )
  end

  def rebucket_field(field)
    payload = build_policy_payload(field)
    dependency_payloads = build_dependency_payloads(field)
    context = { "dependency_payloads" => dependency_payloads }

    FieldReadinessPolicy.new.call(payload, context: context)
  end

  def build_policy_payload(field)
    span = field.source_span || {}
    {
      "field_key" => field.field_key,
      "field_index" => field.field_index,
      "value" => field.extracted_value,
      "confidence_score" => field.confidence_score,
      "source_type" => field.source_type,
      "classification" => field.classification,
      "field_family" => field.field_family,
      "gates_activation" => field.gates_activation,
      "conflict_candidate" => field.contract_review_conflicts.open.exists?,
      "source_quality" => field.source_quality_flag,
      "source_excerpt" => span["excerpt"],
      "precedence_hint" => span["precedence_hint"],
      "supersedes_prior_value" => span["supersedes_prior_value"],
      "derived_input_keys" => field.derived_dependency_keys
    }
  end

  def build_dependency_payloads(field)
    field.derived_dependency_keys.each_with_object({}) do |dep_key, hash|
      dep_field = find_dependency_field(field, dep_key)
      next unless dep_field

      hash[dep_key] ||= []
      hash[dep_key] << {
        "value" => dep_field.effective_value,
        "confidence_score" => dep_field.confidence_score,
        "review_status" => dep_field.review_status
      }
    end
  end

  def create_field_audit!(field, action, review_status:, note:)
    status_phrase = @review.completed? ? "after review completion" : "during review"
    details = "#{review_action_label(review_status)} #{human_field_label(field)} #{status_phrase}."
    details = "#{details} Note: #{note}" if note.present?

    AuditLog.create!(
      organization: @contract.organization,
      user: @user,
      contract: @contract,
      action: action,
      details: details
    )
  end

  def create_review_audit!(action, details)
    AuditLog.create!(organization: @contract.organization, user: @user, contract: @contract, action:, details:)
  end

  def review_action_label(review_status)
    {
      "confirmed" => "Confirmed",
      "edited" => "Edited",
      "not_found" => "Marked",
      "not_applicable" => "Marked"
    }.fetch(review_status)
  end

  def human_field_label(field)
    field.field_key.split(".").last.tr("_", " ")
  end

  def default_resolution_note(field)
    "Resolved during human review for #{field.field_key}."
  end

  def pending_field_count
    reviewable_fields.where(review_status: "pending").count
  end

  def reviewable_fields
    ContractReviewField.unscoped.where(contract_review_id: @review.id)
  end

  def derived_fields
    reviewable_fields.where(source_type: "derived").order(:field_key, :field_index)
  end
end
