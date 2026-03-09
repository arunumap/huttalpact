# frozen_string_literal: true

class ReviewFieldCatalog
  FieldEntry = Data.define(
    :field_name,
    :display_name,
    :field_group,
    :value_type,
    :enum_options,
    :lease_only,
    :position
  )

  FIELD_GROUPS = %w[core dates financial lease_space cam ti escalations options milestones clauses].freeze

  FIELD_GROUP_LABELS = {
    "core" => "Core Details",
    "dates" => "Dates & Timeline",
    "financial" => "Financial Terms",
    "lease_space" => "Space & Use",
    "cam" => "CAM / Operating Expenses",
    "ti" => "Tenant Improvements",
    "escalations" => "Rent Escalations",
    "options" => "Lease Options",
    "milestones" => "Milestones",
    "clauses" => "Key Clauses"
  }.freeze

  FIELDS = [
    # === Core ===
    FieldEntry.new(field_name: "title", display_name: "Title", field_group: "core",
                   value_type: "string", enum_options: nil, lease_only: false, position: 0),
    FieldEntry.new(field_name: "vendor_name", display_name: "Vendor / Landlord", field_group: "core",
                   value_type: "string", enum_options: nil, lease_only: false, position: 1),
    FieldEntry.new(field_name: "premises_address", display_name: "Premises Address", field_group: "core",
                   value_type: "string", enum_options: nil, lease_only: false, position: 2),
    FieldEntry.new(field_name: "contract_type", display_name: "Contract Type", field_group: "core",
                   value_type: "enum", enum_options: %w[lease service_agreement maintenance insurance software other],
                   lease_only: false, position: 3),
    FieldEntry.new(field_name: "direction", display_name: "Direction", field_group: "core",
                   value_type: "enum", enum_options: %w[inbound outbound], lease_only: false, position: 4),

    # === Dates ===
    FieldEntry.new(field_name: "start_date", display_name: "Start Date", field_group: "dates",
                   value_type: "date", enum_options: nil, lease_only: false, position: 0),
    FieldEntry.new(field_name: "end_date", display_name: "End Date", field_group: "dates",
                   value_type: "date", enum_options: nil, lease_only: false, position: 1),
    FieldEntry.new(field_name: "next_renewal_date", display_name: "Next Renewal Date", field_group: "dates",
                   value_type: "date", enum_options: nil, lease_only: false, position: 2),
    FieldEntry.new(field_name: "lease_details.rent_commencement_date", display_name: "Rent Commencement Date",
                   field_group: "dates", value_type: "date", enum_options: nil, lease_only: true, position: 3),

    # === Financial ===
    FieldEntry.new(field_name: "monthly_value", display_name: "Monthly Value", field_group: "financial",
                   value_type: "currency", enum_options: nil, lease_only: false, position: 0),
    FieldEntry.new(field_name: "total_value", display_name: "Total Value", field_group: "financial",
                   value_type: "currency", enum_options: nil, lease_only: false, position: 1),
    FieldEntry.new(field_name: "auto_renews", display_name: "Auto-Renews", field_group: "financial",
                   value_type: "boolean", enum_options: nil, lease_only: false, position: 2),
    FieldEntry.new(field_name: "renewal_term", display_name: "Renewal Term", field_group: "financial",
                   value_type: "enum", enum_options: %w[month-to-month annual 2-year custom],
                   lease_only: false, position: 3),
    FieldEntry.new(field_name: "notice_period_days", display_name: "Notice Period (Days)", field_group: "financial",
                   value_type: "number", enum_options: nil, lease_only: false, position: 4),

    # === Lease Space ===
    FieldEntry.new(field_name: "lease_details.lease_type", display_name: "Lease Type", field_group: "lease_space",
                   value_type: "enum", enum_options: %w[gross modified_gross nnn percentage],
                   lease_only: true, position: 0),
    FieldEntry.new(field_name: "lease_details.rentable_sqft", display_name: "Rentable Sq Ft",
                   field_group: "lease_space", value_type: "number", enum_options: nil,
                   lease_only: true, position: 1),
    FieldEntry.new(field_name: "lease_details.usable_sqft", display_name: "Usable Sq Ft",
                   field_group: "lease_space", value_type: "number", enum_options: nil,
                   lease_only: true, position: 2),
    FieldEntry.new(field_name: "lease_details.load_factor", display_name: "Load Factor",
                   field_group: "lease_space", value_type: "number", enum_options: nil,
                   lease_only: true, position: 3),
    FieldEntry.new(field_name: "lease_details.permitted_use", display_name: "Permitted Use",
                   field_group: "lease_space", value_type: "text", enum_options: nil,
                   lease_only: true, position: 4),
    FieldEntry.new(field_name: "lease_details.security_deposit", display_name: "Security Deposit",
                   field_group: "lease_space", value_type: "currency", enum_options: nil,
                   lease_only: true, position: 5),
    FieldEntry.new(field_name: "lease_details.security_deposit_conditions", display_name: "Security Deposit Conditions",
                   field_group: "lease_space", value_type: "text", enum_options: nil,
                   lease_only: true, position: 6),
    FieldEntry.new(field_name: "lease_details.parking_spaces", display_name: "Parking Spaces",
                   field_group: "lease_space", value_type: "number", enum_options: nil,
                   lease_only: true, position: 7),
    FieldEntry.new(field_name: "lease_details.parking_monthly_cost", display_name: "Parking Monthly Cost",
                   field_group: "lease_space", value_type: "currency", enum_options: nil,
                   lease_only: true, position: 8),
    FieldEntry.new(field_name: "lease_details.free_rent_months", display_name: "Free Rent Months",
                   field_group: "lease_space", value_type: "number", enum_options: nil,
                   lease_only: true, position: 9),
    FieldEntry.new(field_name: "lease_details.percentage_rent_breakpoint", display_name: "Percentage Rent Breakpoint",
                   field_group: "lease_space", value_type: "currency", enum_options: nil,
                   lease_only: true, position: 10),
    FieldEntry.new(field_name: "lease_details.percentage_rent_rate", display_name: "Percentage Rent Rate",
                   field_group: "lease_space", value_type: "number", enum_options: nil,
                   lease_only: true, position: 11),
    FieldEntry.new(field_name: "lease_details.percentage_rent_report_date", display_name: "Percentage Rent Report Date",
                   field_group: "lease_space", value_type: "date", enum_options: nil,
                   lease_only: true, position: 12),

    # === CAM / Operating Expenses ===
    FieldEntry.new(field_name: "lease_details.cam_base_amount", display_name: "CAM Base Amount",
                   field_group: "cam", value_type: "currency", enum_options: nil,
                   lease_only: true, position: 0),
    FieldEntry.new(field_name: "lease_details.cam_base_year", display_name: "CAM Base Year",
                   field_group: "cam", value_type: "number", enum_options: nil,
                   lease_only: true, position: 1),
    FieldEntry.new(field_name: "lease_details.cam_cap_percentage", display_name: "CAM Cap Percentage",
                   field_group: "cam", value_type: "number", enum_options: nil,
                   lease_only: true, position: 2),
    FieldEntry.new(field_name: "lease_details.cam_cap_type", display_name: "CAM Cap Type",
                   field_group: "cam", value_type: "enum", enum_options: %w[cumulative non_cumulative none],
                   lease_only: true, position: 3),
    FieldEntry.new(field_name: "lease_details.cam_reconciliation_month", display_name: "CAM Reconciliation Month",
                   field_group: "cam", value_type: "number", enum_options: nil,
                   lease_only: true, position: 4),
    FieldEntry.new(field_name: "lease_details.cam_audit_rights", display_name: "CAM Audit Rights",
                   field_group: "cam", value_type: "boolean", enum_options: nil,
                   lease_only: true, position: 5),
    FieldEntry.new(field_name: "lease_details.cam_gross_up_provision", display_name: "Gross-Up Provision",
                   field_group: "cam", value_type: "boolean", enum_options: nil,
                   lease_only: true, position: 6),
    FieldEntry.new(field_name: "lease_details.cam_controllable_cap", display_name: "Controllable Expense Cap",
                   field_group: "cam", value_type: "number", enum_options: nil,
                   lease_only: true, position: 7),

    # === Tenant Improvements ===
    FieldEntry.new(field_name: "lease_details.ti_allowance_psf", display_name: "TI Allowance (per SF)",
                   field_group: "ti", value_type: "currency", enum_options: nil,
                   lease_only: true, position: 0),
    FieldEntry.new(field_name: "lease_details.ti_total_amount", display_name: "TI Total Amount",
                   field_group: "ti", value_type: "currency", enum_options: nil,
                   lease_only: true, position: 1),
    FieldEntry.new(field_name: "lease_details.ti_deadline", display_name: "TI Deadline",
                   field_group: "ti", value_type: "date", enum_options: nil,
                   lease_only: true, position: 2),
    FieldEntry.new(field_name: "lease_details.ti_disbursement_type", display_name: "TI Disbursement Type",
                   field_group: "ti", value_type: "enum", enum_options: %w[lump_sum draw_schedule reimbursement],
                   lease_only: true, position: 3),
    FieldEntry.new(field_name: "lease_details.ti_amortization_rate", display_name: "TI Amortization Rate",
                   field_group: "ti", value_type: "number", enum_options: nil,
                   lease_only: true, position: 4),
    FieldEntry.new(field_name: "lease_details.ti_amortization_term_months", display_name: "TI Amortization Term (Months)",
                   field_group: "ti", value_type: "number", enum_options: nil,
                   lease_only: true, position: 5),
    FieldEntry.new(field_name: "lease_details.ti_landlord_work_description", display_name: "Landlord Work Description",
                   field_group: "ti", value_type: "text", enum_options: nil,
                   lease_only: true, position: 6),
    FieldEntry.new(field_name: "lease_details.ti_tenant_work_description", display_name: "Tenant Work Description",
                   field_group: "ti", value_type: "text", enum_options: nil,
                   lease_only: true, position: 7),

    # === Rent Escalations ===
    FieldEntry.new(field_name: "rent_escalations", display_name: "Rent Escalations", field_group: "escalations",
                   value_type: "array", enum_options: nil, lease_only: true, position: 0),

    # === Lease Options ===
    FieldEntry.new(field_name: "lease_options", display_name: "Lease Options", field_group: "options",
                   value_type: "array", enum_options: nil, lease_only: true, position: 0),

    # === Milestones ===
    FieldEntry.new(field_name: "lease_milestones", display_name: "Milestones", field_group: "milestones",
                   value_type: "array", enum_options: nil, lease_only: true, position: 0),

    # === Key Clauses ===
    FieldEntry.new(field_name: "key_clauses", display_name: "Key Clauses", field_group: "clauses",
                   value_type: "array", enum_options: nil, lease_only: false, position: 0)
  ].freeze

  FIELDS_BY_NAME = FIELDS.index_by(&:field_name).freeze
  FIELDS_BY_GROUP = FIELDS.group_by(&:field_group).freeze

  class << self
    def all
      FIELDS
    end

    def find(field_name)
      FIELDS_BY_NAME[field_name]
    end

    def for_group(group)
      FIELDS_BY_GROUP[group] || []
    end

    def for_contract_type(contract_type)
      if contract_type == "lease"
        FIELDS
      else
        FIELDS.reject(&:lease_only)
      end
    end

    def groups_for_contract_type(contract_type)
      fields = for_contract_type(contract_type)
      FIELD_GROUPS.filter_map do |group|
        group_fields = fields.select { |f| f.field_group == group }
        next if group_fields.empty?

        { key: group, label: FIELD_GROUP_LABELS[group], fields: group_fields.sort_by(&:position) }
      end
    end

    def field_names
      FIELDS.map(&:field_name)
    end

    def enum_options_for(field_name)
      FIELDS_BY_NAME[field_name]&.enum_options
    end
  end
end
