class ContractReviewCompletionService
  class ReviewIncompleteError < StandardError; end

  def initialize(review:, user:)
    @review = review
    @contract = review.contract
    @user = user
  end

  def call
    validate_completable!

    ActiveRecord::Base.transaction do
      @contract.lock!

      # Auto-accept remaining confident fields that are still pending
      auto_accept_confident_fields!

      apply_contract_fields
      apply_lease_detail_fields if lease_contract?
      apply_rent_escalations if has_field?("rent_escalations")
      apply_lease_options if has_field?("lease_options")
      apply_lease_milestones if has_field?("lease_milestones")
      apply_key_clauses if has_field?("key_clauses")

      compute_next_renewal_date!
      complete_review!
      activate_contract!
      create_audit_log

      GenerateContractAlertsJob.perform_later(@contract.id)
    end

    @review
  end

  private

  CONTRACT_FIELD_MAP = {
    "title" => :title,
    "vendor_name" => :vendor_name,
    "premises_address" => :premises_address,
    "contract_type" => :contract_type,
    "direction" => :direction,
    "start_date" => :start_date,
    "end_date" => :end_date,
    "next_renewal_date" => :next_renewal_date,
    "monthly_value" => :monthly_value,
    "total_value" => :total_value,
    "auto_renews" => :auto_renews,
    "renewal_term" => :renewal_term,
    "notice_period_days" => :notice_period_days
  }.freeze

  LEASE_DETAIL_FIELDS = %w[
    lease_type rentable_sqft usable_sqft load_factor permitted_use
    security_deposit security_deposit_conditions parking_spaces parking_monthly_cost
    free_rent_months rent_commencement_date percentage_rent_breakpoint percentage_rent_rate
    percentage_rent_report_date cam_base_amount cam_base_year cam_cap_percentage cam_cap_type
    cam_reconciliation_month cam_audit_rights cam_gross_up_provision cam_controllable_cap
    ti_allowance_psf ti_total_amount ti_deadline ti_disbursement_type
    ti_amortization_rate ti_amortization_term_months ti_landlord_work_description ti_tenant_work_description
  ].freeze

  LEASE_BOOLEAN_FIELDS = %w[cam_audit_rights cam_gross_up_provision].freeze

  def validate_completable!
    raise ReviewIncompleteError, "Not all required fields have been reviewed" unless @review.all_required_fields_reviewed?
    raise ReviewIncompleteError, "Review is already completed" if @review.completed?
  end

  def auto_accept_confident_fields!
    @review.fields.confident.pending.find_each do |field|
      field.update!(
        status: "auto_accepted",
        reviewed_at: Time.current,
        reviewed_by: @user
      )
    end
    update_reviewed_count!
  end

  def apply_contract_fields
    update_attrs = {}

    CONTRACT_FIELD_MAP.each do |field_name, attr_name|
      field = find_field(field_name)
      next unless field

      value = parse_final_value(field)
      next if value.nil? && field.status.in?(%w[not_found not_applicable])

      update_attrs[attr_name] = value unless value.nil?
    end

    @contract.update!(update_attrs) if update_attrs.any?
  end

  def apply_lease_detail_fields
    attrs = {}

    LEASE_DETAIL_FIELDS.each do |attr|
      field = find_field("lease_details.#{attr}")
      next unless field

      value = parse_final_value(field)
      value = false if attr.in?(LEASE_BOOLEAN_FIELDS) && value.nil?
      attrs[attr.to_sym] = value
    end

    return if attrs.empty?

    @contract.lease_detail&.destroy
    @contract.create_lease_detail!(attrs)
  end

  def apply_rent_escalations
    field = find_field("rent_escalations")
    return unless field

    escalations = parse_final_value(field)
    return unless escalations.is_a?(Array)

    @contract.rent_escalations.destroy_all
    escalations.each_with_index do |esc, idx|
      next unless esc.is_a?(Hash)

      @contract.rent_escalations.create!(
        effective_date: esc["effective_date"],
        base_rent_monthly: esc["base_rent_monthly"],
        base_rent_annual: esc["base_rent_annual"],
        escalation_type: esc["escalation_type"],
        escalation_value: esc["escalation_value"],
        description: esc["description"],
        position: idx
      )
    end
  end

  def apply_lease_options
    field = find_field("lease_options")
    return unless field

    options = parse_final_value(field)
    return unless options.is_a?(Array)

    @contract.lease_options.destroy_all
    options.each_with_index do |opt, idx|
      next unless opt.is_a?(Hash)

      @contract.lease_options.create!(
        option_type: opt["option_type"],
        exercise_deadline: opt["exercise_deadline"],
        notice_deadline: opt["notice_deadline"],
        term_length_months: opt["term_length_months"],
        rent_terms: opt["rent_terms"],
        penalty_amount: opt["penalty_amount"],
        conditions: opt["conditions"],
        position: idx
      )
    end
  end

  def apply_lease_milestones
    field = find_field("lease_milestones")
    return unless field

    milestones = parse_final_value(field)
    return unless milestones.is_a?(Array)

    @contract.lease_milestones.destroy_all
    milestones.each do |ms|
      next unless ms.is_a?(Hash)

      @contract.lease_milestones.create!(
        organization: @contract.organization,
        milestone_type: ms["milestone_type"],
        due_date: ms["due_date"],
        description: ms["description"],
        recurring: ms["recurring"] || false,
        recurrence_interval: ms["recurrence_interval"]
      )
    end
  end

  def apply_key_clauses
    field = find_field("key_clauses")
    return unless field

    clauses = parse_final_value(field)
    return unless clauses.is_a?(Array)

    @contract.key_clauses.destroy_all
    clauses.each do |clause|
      next unless clause.is_a?(Hash)
      next unless clause["clause_type"].present? && clause["content"].present?
      next unless KeyClause::CLAUSE_TYPES.include?(clause["clause_type"])

      @contract.key_clauses.create!(
        clause_type: clause["clause_type"],
        content: clause["content"],
        page_reference: clause["page_reference"],
        confidence_score: clause["confidence_score"],
        source_document_id: nil
      )
    end
  end

  def complete_review!
    @review.update!(
      status: "completed",
      completed_at: Time.current,
      completed_by: @user,
      reviewed_fields: @review.fields.reviewed.count
    )
  end

  def activate_contract!
    new_status = @contract.draft? || @contract.in_review? ? "active" : @contract.status
    @contract.update!(status: new_status) if @contract.status != new_status
  end

  def compute_next_renewal_date!
    return if @contract.next_renewal_date.present?
    return unless @contract.auto_renews? && @contract.end_date.present?

    @contract.update!(next_renewal_date: @contract.end_date)
  end

  def create_audit_log
    AuditLog.create!(
      organization: @contract.organization,
      user: @user,
      contract: @contract,
      action: "review_completed",
      details: {
        review_id: @review.id,
        review_type: @review.review_type,
        total_fields: @review.total_fields,
        reviewed_fields: @review.reviewed_fields,
        auto_accepted_count: @review.fields.auto_accepted.count,
        edited_count: @review.fields.edited.count,
        confirmed_count: @review.fields.confirmed.count,
        not_found_count: @review.fields.not_found.count,
        not_applicable_count: @review.fields.not_applicable.count
      }
    )
  end

  def update_reviewed_count!
    @review.update!(reviewed_fields: @review.fields.reviewed.count)
  end

  def find_field(field_name)
    @fields_by_name ||= @review.fields.index_by(&:field_name)
    @fields_by_name[field_name]
  end

  def has_field?(field_name)
    find_field(field_name).present?
  end

  def lease_contract?
    @contract.contract_type == "lease"
  end

  def parse_final_value(field)
    raw = field.final_value
    return nil if raw.nil?

    JSON.parse(raw)
  rescue JSON::ParserError => e
    Rails.logger.error(
      "ContractReviewCompletionService JSON parse failed for " \
        "field #{field.field_name} (id=#{field.id}): #{e.message}"
    )
    raw
  end
end
