class ContractReviewValueResolver
  DATE_FIELD_KEYS = %w[
    contract.end_date
    contract.next_renewal_date
    lease_detail.ti_deadline
    lease_detail.percentage_rent_report_date
    rent_escalation.effective_date
    lease_option.notice_deadline
    lease_option.exercise_deadline
    lease_milestone.due_date
    contract.next_renewal_date_fallback
    notice_period_start_date
    cam_reconciliation_alert_date
    recurring_milestone_next_occurrence_date
  ].freeze
  INTEGER_FIELD_KEYS = %w[
    contract.notice_period_days
    lease_detail.parking_spaces
    lease_detail.free_rent_months
    lease_detail.cam_base_year
    lease_detail.cam_reconciliation_month
    lease_detail.ti_amortization_term_months
    lease_option.term_length_months
  ].freeze
  DECIMAL_FIELD_KEYS = %w[
    contract.monthly_value
    contract.total_value
    lease_detail.rentable_sqft
    lease_detail.usable_sqft
    lease_detail.load_factor
    lease_detail.security_deposit
    lease_detail.parking_monthly_cost
    lease_detail.percentage_rent_breakpoint
    lease_detail.percentage_rent_rate
    lease_detail.cam_base_amount
    lease_detail.cam_cap_percentage
    lease_detail.cam_controllable_cap
    lease_detail.ti_allowance_psf
    lease_detail.ti_total_amount
    lease_detail.ti_amortization_rate
    rent_escalation.base_rent_monthly
    rent_escalation.base_rent_annual
    rent_escalation.escalation_value
    lease_option.penalty_amount
  ].freeze

  def initialize(contract)
    @contract = contract
  end

  def snapshot
    {
      "title" => @contract.title,
      "vendor_name" => @contract.vendor_name,
      "premises_address" => @contract.premises_address,
      "contract_type" => @contract.contract_type,
      "direction" => @contract.direction,
      "start_date" => serialize_value(@contract.start_date),
      "end_date" => serialize_value(@contract.end_date),
      "next_renewal_date" => serialize_value(@contract.next_renewal_date),
      "monthly_value" => serialize_value(@contract.monthly_value),
      "total_value" => serialize_value(@contract.total_value),
      "auto_renews" => @contract.auto_renews,
      "renewal_term" => @contract.renewal_term,
      "notice_period_days" => @contract.notice_period_days,
      "summary" => @contract.ai_summary,
      "lease_details" => serialize_lease_detail,
      "rent_escalations" => serialize_collection(@contract.rent_escalations.order(:position, :created_at), %w[
        effective_date base_rent_monthly base_rent_annual escalation_type escalation_value description
      ]),
      "lease_options" => serialize_collection(@contract.lease_options.order(:position, :created_at), %w[
        option_type exercise_deadline notice_deadline term_length_months rent_terms penalty_amount conditions
      ]),
      "lease_milestones" => serialize_collection(@contract.lease_milestones.order(:created_at), %w[
        milestone_type due_date description recurring recurrence_interval
      ])
    }
  end

  def assign_value(data:, field_key:, value:, field_index: nil)
    serialized_value = serialize_value(value)

    case field_key
    when /^contract\./
      data[field_key.split(".").last] = serialized_value
    when /^lease_detail\./
      data["lease_details"] ||= {}
      data["lease_details"][field_key.split(".").last] = serialized_value
    when /^rent_escalation\./
      assign_collection_value!(data, "rent_escalations", field_key, serialized_value, field_index)
    when /^lease_option\./
      assign_collection_value!(data, "lease_options", field_key, serialized_value, field_index)
    when /^lease_milestone\./
      assign_collection_value!(data, "lease_milestones", field_key, serialized_value, field_index)
    else
      raise ArgumentError, "Unsupported review field key: #{field_key}"
    end

    data
  end

  def derived_value(field_key, data:, field_index: nil)
    case field_key
    when "contract.next_renewal_date_fallback"
      compute_next_renewal_date_fallback(data)
    when "notice_period_start_date"
      compute_notice_period_start_date(data)
    when "cam_reconciliation_alert_date"
      compute_cam_reconciliation_alert_date(data)
    when "recurring_milestone_next_occurrence_date"
      milestone = Array(data["lease_milestones"])[field_index].to_h
      compute_recurring_milestone_next_occurrence(milestone)
    else
      nil
    end
  end

  def normalize_input(field:, raw_value:)
    return nil if raw_value.is_a?(String) && raw_value.strip.blank?
    return nil if raw_value.nil?

    if date_field?(field)
      parse_date_string(raw_value)&.iso8601 or raise ArgumentError, "Enter a valid date."
    elsif boolean_field?(field)
      normalize_boolean(raw_value)
    elsif integer_field?(field)
      Integer(raw_value)
    elsif decimal_field?(field)
      BigDecimal(raw_value.to_s).to_f
    else
      raw_value.to_s.strip.presence
    end
  rescue ArgumentError
    raise
  rescue StandardError
    raise ArgumentError, "Enter a valid value for #{field.field_key.tr('.', ' ')}."
  end

  def boolean_field?(field)
    field.field_family == "alert_governing_boolean" || sampled_values(field).any? { |value| value.in?([ true, false ]) }
  end

  def date_field?(field)
    DATE_FIELD_KEYS.include?(field.field_key) || sampled_values(field).any? { |value| value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/) }
  end

  def integer_field?(field)
    INTEGER_FIELD_KEYS.include?(field.field_key) || sampled_values(field).any? { |value| value.is_a?(Integer) }
  end

  def decimal_field?(field)
    DECIMAL_FIELD_KEYS.include?(field.field_key) || sampled_values(field).any? { |value| value.is_a?(Float) || value.is_a?(BigDecimal) }
  end

  private

  def sampled_values(field)
    [ field.approved_value, field.extracted_value, field.current_value ].compact
  end

  def assign_collection_value!(data, collection_key, field_key, value, field_index)
    index = Integer(field_index)
    data[collection_key] ||= []
    data[collection_key][index] ||= {}
    data[collection_key][index][field_key.split(".").last] = value
  end

  def compute_next_renewal_date_fallback(data)
    return nil unless normalize_boolean(data["auto_renews"])
    return nil if data["next_renewal_date"].present?

    parse_date_string(data["end_date"])&.iso8601
  end

  def compute_notice_period_start_date(data)
    notice_period_days = data["notice_period_days"]
    return nil if notice_period_days.blank?

    reference_date = data["next_renewal_date"].presence || compute_next_renewal_date_fallback(data) || data["end_date"]
    parsed_reference = parse_date_string(reference_date)
    return nil unless parsed_reference

    (parsed_reference - notice_period_days.to_i).iso8601
  end

  def compute_cam_reconciliation_alert_date(data)
    month = Integer(data.dig("lease_details", "cam_reconciliation_month")) rescue nil
    return nil unless month&.between?(1, 12)

    candidate = Date.new(Date.current.year, month, 1)
    candidate = candidate.next_year if candidate < Date.current.beginning_of_month
    candidate.iso8601
  end

  def compute_recurring_milestone_next_occurrence(milestone)
    due_date = parse_date_string(milestone["due_date"])
    return nil unless due_date
    return due_date.iso8601 unless normalize_boolean(milestone["recurring"])

    months = case milestone["recurrence_interval"]
    when "monthly" then 1
    when "quarterly" then 3
    when "annual" then 12
    end
    return due_date.iso8601 unless months

    candidate = due_date
    candidate = candidate >> months while candidate < Date.current
    candidate.iso8601
  end

  def normalize_boolean(value)
    return value if value.is_a?(TrueClass) || value.is_a?(FalseClass)
    return nil if value.nil?

    ActiveModel::Type::Boolean.new.cast(value)
  end

  def parse_date_string(value)
    return if value.blank?

    Date.parse(value.to_s)
  rescue Date::Error, ArgumentError
    nil
  end

  def serialize_lease_detail
    return nil unless @contract.lease_detail

    %w[
      lease_type rentable_sqft usable_sqft load_factor permitted_use security_deposit
      security_deposit_conditions parking_spaces parking_monthly_cost free_rent_months
      rent_commencement_date percentage_rent_breakpoint percentage_rent_rate
      percentage_rent_report_date cam_base_amount cam_base_year cam_cap_percentage
      cam_cap_type cam_reconciliation_month cam_audit_rights cam_gross_up_provision
      cam_controllable_cap ti_allowance_psf ti_total_amount ti_deadline
      ti_disbursement_type ti_amortization_rate ti_amortization_term_months
      ti_landlord_work_description ti_tenant_work_description
    ].index_with { |attribute| serialize_value(@contract.lease_detail.public_send(attribute)) }
  end

  def serialize_collection(collection, attributes)
    collection.map do |record|
      attributes.index_with { |attribute| serialize_value(record.public_send(attribute)) }
    end
  end

  def serialize_value(value)
    case value
    when Date, Time, DateTime
      value.iso8601
    when BigDecimal
      value.to_f
    else
      value
    end
  end
end
