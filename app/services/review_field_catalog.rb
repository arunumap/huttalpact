class ReviewFieldCatalog
  FieldDefinition = Struct.new(
    :key,
    :classification,
    :field_family,
    :source_type,
    :alert_families,
    :dependencies,
    :repeatable,
    :blocks_activation,
    :lease_only,
    :notes,
    keyword_init: true
  ) do
    def direct?
      source_type == "direct"
    end

    def derived?
      source_type == "derived"
    end

    def app_managed?
      source_type == "app_managed"
    end

    def repeatable?
      !!repeatable
    end

    def blocks_activation?
      !!blocks_activation
    end

    def lease_only?
      !!lease_only
    end

    def applicable_to_contract_type?(contract_type)
      return true unless lease_only?

      contract_type.to_s == "lease"
    end
  end

  AlertFamilyDefinition = Struct.new(
    :key,
    :required_fields,
    :governing_fields,
    :derived_fields,
    :lease_only,
    :notes,
    keyword_init: true
  ) do
    def lease_only?
      !!lease_only
    end

    def applicable_to_contract_type?(contract_type)
      return true unless lease_only?

      contract_type.to_s == "lease"
    end

    def field_keys
      (required_fields + governing_fields + derived_fields).uniq
    end
  end

  CLASSIFICATIONS = %w[alert_driving alert_governing contextual app_managed].freeze
  FIELD_FAMILIES = %w[
    alert_date
    alert_governing_boolean
    alert_governing_enum
    alert_governing_recurrence
    contextual_date
    derived_date
    app_managed
  ].freeze

  class << self
    def fields
      @fields ||= build_fields
    end

    def field(field_key)
      fields.fetch(normalize_key(field_key))
    end
    alias_method :fetch, :field

    def alert_families
      @alert_families ||= build_alert_families
    end

    def alert_family(alert_key)
      alert_families.fetch(normalize_key(alert_key))
    end

    def fields_for_alert(alert_key)
      alert_family(alert_key).field_keys.map { |field_key| field(field_key) }
    end

    def applicable_alert_families(contract_type:)
      alert_families.values.select { |family| family.applicable_to_contract_type?(contract_type) }
    end

    def tracked_direct_fields
      @tracked_direct_fields ||= fields.values.select(&:direct?).freeze
    end

    def review_prompt_field_groups
      @review_prompt_field_groups ||= {
        contract_level: tracked_direct_fields
          .reject(&:repeatable?)
          .select { |definition| definition.key.start_with?("contract.") }
          .map(&:key)
          .freeze,
        lease_detail: tracked_direct_fields
          .reject(&:repeatable?)
          .select { |definition| definition.key.start_with?("lease_detail.") }
          .map(&:key)
          .freeze,
        repeatable: tracked_direct_fields
          .select(&:repeatable?)
          .map(&:key)
          .freeze
      }.freeze
    end

    def lease_only_field_keys
      fields.values.select(&:lease_only?).map(&:key)
    end

    private

    def build_fields
      {
        "contract.end_date" => build_field(
          key: "contract.end_date",
          classification: "alert_driving",
          field_family: "alert_date",
          source_type: "direct",
          alert_families: %w[expiry_warning notice_period_start],
          blocks_activation: true,
          notes: "Base deadline and fallback reference date for notice logic."
        ),
        "contract.next_renewal_date" => build_field(
          key: "contract.next_renewal_date",
          classification: "alert_driving",
          field_family: "alert_date",
          source_type: "direct",
          alert_families: %w[renewal_upcoming notice_period_start],
          blocks_activation: true,
          notes: "Primary renewal date when the renewal workflow applies."
        ),
        "contract.auto_renews" => build_field(
          key: "contract.auto_renews",
          classification: "alert_governing",
          field_family: "alert_governing_boolean",
          source_type: "direct",
          alert_families: %w[renewal_upcoming notice_period_start],
          blocks_activation: true,
          notes: "Governs whether next_renewal_date fallback is allowed."
        ),
        "contract.notice_period_days" => build_field(
          key: "contract.notice_period_days",
          classification: "alert_driving",
          field_family: "alert_date",
          source_type: "direct",
          alert_families: %w[notice_period_start],
          blocks_activation: true,
          notes: "Used to compute notice_period_start_date."
        ),
        "contract.contract_type" => build_field(
          key: "contract.contract_type",
          classification: "alert_governing",
          field_family: "alert_governing_enum",
          source_type: "direct",
          alert_families: %w[option_exercise_deadline rent_escalation_date cam_reconciliation ti_deadline milestone_reminder],
          blocks_activation: true,
          notes: "Lease-only alert families only apply when contract_type is lease."
        ),
        "lease_detail.cam_reconciliation_month" => build_field(
          key: "lease_detail.cam_reconciliation_month",
          classification: "alert_driving",
          field_family: "alert_date",
          source_type: "direct",
          alert_families: %w[cam_reconciliation],
          blocks_activation: true,
          lease_only: true,
          notes: "Computes the next calendar occurrence for CAM alerting."
        ),
        "lease_detail.ti_deadline" => build_field(
          key: "lease_detail.ti_deadline",
          classification: "alert_driving",
          field_family: "alert_date",
          source_type: "direct",
          alert_families: %w[ti_deadline],
          blocks_activation: true,
          lease_only: true,
          notes: "Lease-only date field for TI deadline alerting."
        ),
        "lease_detail.percentage_rent_report_date" => build_field(
          key: "lease_detail.percentage_rent_report_date",
          classification: "contextual",
          field_family: "contextual_date",
          source_type: "direct",
          lease_only: true,
          notes: "Stored and reviewable, but does not currently drive alert activation."
        ),
        "rent_escalation.effective_date" => build_field(
          key: "rent_escalation.effective_date",
          classification: "alert_driving",
          field_family: "alert_date",
          source_type: "direct",
          alert_families: %w[rent_escalation_date],
          repeatable: true,
          blocks_activation: true,
          lease_only: true,
          notes: "Only future effective dates produce rent escalation alerts."
        ),
        "lease_option.notice_deadline" => build_field(
          key: "lease_option.notice_deadline",
          classification: "alert_driving",
          field_family: "alert_date",
          source_type: "direct",
          alert_families: %w[option_exercise_deadline],
          repeatable: true,
          blocks_activation: true,
          lease_only: true,
          notes: "Option-related date actually used for alerting."
        ),
        "lease_option.exercise_deadline" => build_field(
          key: "lease_option.exercise_deadline",
          classification: "contextual",
          field_family: "contextual_date",
          source_type: "direct",
          repeatable: true,
          lease_only: true,
          notes: "Stored and reviewable, but does not currently drive alert activation."
        ),
        "lease_milestone.due_date" => build_field(
          key: "lease_milestone.due_date",
          classification: "alert_driving",
          field_family: "alert_date",
          source_type: "direct",
          alert_families: %w[milestone_reminder],
          repeatable: true,
          blocks_activation: true,
          lease_only: true,
          notes: "Raw date input for milestone reminders."
        ),
        "lease_milestone.recurring" => build_field(
          key: "lease_milestone.recurring",
          classification: "alert_governing",
          field_family: "alert_governing_boolean",
          source_type: "direct",
          alert_families: %w[milestone_reminder],
          repeatable: true,
          blocks_activation: true,
          lease_only: true,
          notes: "Determines whether recurring milestone computation should be applied."
        ),
        "lease_milestone.recurrence_interval" => build_field(
          key: "lease_milestone.recurrence_interval",
          classification: "alert_governing",
          field_family: "alert_governing_recurrence",
          source_type: "direct",
          alert_families: %w[milestone_reminder],
          repeatable: true,
          blocks_activation: true,
          lease_only: true,
          notes: "Required when a recurring milestone exists."
        ),
        "notice_period_start_date" => build_field(
          key: "notice_period_start_date",
          classification: "alert_driving",
          field_family: "derived_date",
          source_type: "derived",
          alert_families: %w[notice_period_start],
          dependencies: %w[contract.notice_period_days contract.next_renewal_date contract.end_date contract.next_renewal_date_fallback],
          blocks_activation: true,
          notes: "Derived from notice_period_days plus next_renewal_date or end_date."
        ),
        "cam_reconciliation_alert_date" => build_field(
          key: "cam_reconciliation_alert_date",
          classification: "alert_driving",
          field_family: "derived_date",
          source_type: "derived",
          alert_families: %w[cam_reconciliation],
          dependencies: %w[contract.contract_type lease_detail.cam_reconciliation_month],
          blocks_activation: true,
          lease_only: true,
          notes: "Derived next calendar occurrence for CAM reconciliation."
        ),
        "recurring_milestone_next_occurrence_date" => build_field(
          key: "recurring_milestone_next_occurrence_date",
          classification: "alert_driving",
          field_family: "derived_date",
          source_type: "derived",
          alert_families: %w[milestone_reminder],
          dependencies: %w[lease_milestone.due_date lease_milestone.recurring lease_milestone.recurrence_interval],
          repeatable: true,
          blocks_activation: true,
          lease_only: true,
          notes: "Used when a recurring milestone's original due_date is already in the past."
        ),
        "contract.next_renewal_date_fallback" => build_field(
          key: "contract.next_renewal_date_fallback",
          classification: "alert_driving",
          field_family: "derived_date",
          source_type: "derived",
          alert_families: %w[renewal_upcoming notice_period_start],
          dependencies: %w[contract.auto_renews contract.end_date],
          blocks_activation: true,
          notes: "Only allowed when next_renewal_date is blank and auto_renews is true."
        ),
        "contract.status" => build_field(
          key: "contract.status",
          classification: "app_managed",
          field_family: "app_managed",
          source_type: "app_managed",
          notes: "Operational suppression only; expired and cancelled suppress alerts."
        )
      }.freeze
    end

    def build_alert_families
      {
        "expiry_warning" => build_alert_family(
          key: "expiry_warning",
          required_fields: %w[contract.end_date],
          notes: "Base expiry alert family."
        ),
        "renewal_upcoming" => build_alert_family(
          key: "renewal_upcoming",
          required_fields: %w[contract.next_renewal_date],
          governing_fields: %w[contract.auto_renews],
          derived_fields: %w[contract.next_renewal_date_fallback],
          notes: "Uses fallback only when next_renewal_date is blank and auto_renews permits it."
        ),
        "notice_period_start" => build_alert_family(
          key: "notice_period_start",
          required_fields: %w[contract.notice_period_days contract.end_date contract.next_renewal_date],
          governing_fields: %w[contract.auto_renews],
          derived_fields: %w[notice_period_start_date contract.next_renewal_date_fallback],
          notes: "Reference date prefers next_renewal_date and falls back to end_date when allowed."
        ),
        "option_exercise_deadline" => build_alert_family(
          key: "option_exercise_deadline",
          required_fields: %w[lease_option.notice_deadline],
          governing_fields: %w[contract.contract_type],
          lease_only: true,
          notes: "Lease-only family keyed off option notice deadlines."
        ),
        "rent_escalation_date" => build_alert_family(
          key: "rent_escalation_date",
          required_fields: %w[rent_escalation.effective_date],
          governing_fields: %w[contract.contract_type],
          lease_only: true,
          notes: "Lease-only family for future rent escalation dates."
        ),
        "cam_reconciliation" => build_alert_family(
          key: "cam_reconciliation",
          required_fields: %w[lease_detail.cam_reconciliation_month],
          governing_fields: %w[contract.contract_type],
          derived_fields: %w[cam_reconciliation_alert_date],
          lease_only: true,
          notes: "Lease-only family derived from CAM reconciliation month."
        ),
        "ti_deadline" => build_alert_family(
          key: "ti_deadline",
          required_fields: %w[lease_detail.ti_deadline],
          governing_fields: %w[contract.contract_type],
          lease_only: true,
          notes: "Lease-only family for TI deadlines."
        ),
        "milestone_reminder" => build_alert_family(
          key: "milestone_reminder",
          required_fields: %w[lease_milestone.due_date],
          governing_fields: %w[contract.contract_type lease_milestone.recurring lease_milestone.recurrence_interval],
          derived_fields: %w[recurring_milestone_next_occurrence_date],
          lease_only: true,
          notes: "Lease-only family for milestone due dates and recurring milestone roll-forward logic."
        )
      }.freeze
    end

    def build_field(key:, classification:, field_family:, source_type:, alert_families: [], dependencies: [], repeatable: false, blocks_activation: false, lease_only: false, notes: nil)
      FieldDefinition.new(
        key: normalize_key(key),
        classification: classification,
        field_family: field_family,
        source_type: source_type,
        alert_families: freeze_array(alert_families),
        dependencies: freeze_array(dependencies),
        repeatable: repeatable,
        blocks_activation: blocks_activation,
        lease_only: lease_only,
        notes: notes
      ).freeze
    end

    def build_alert_family(key:, required_fields:, governing_fields: [], derived_fields: [], lease_only: false, notes: nil)
      AlertFamilyDefinition.new(
        key: normalize_key(key),
        required_fields: freeze_array(required_fields),
        governing_fields: freeze_array(governing_fields),
        derived_fields: freeze_array(derived_fields),
        lease_only: lease_only,
        notes: notes
      ).freeze
    end

    def freeze_array(values)
      Array(values).map { |value| normalize_key(value) }.freeze
    end

    def normalize_key(key)
      key.to_s
    end
  end
end
