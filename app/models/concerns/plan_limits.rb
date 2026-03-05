module PlanLimits
  extend ActiveSupport::Concern

  ExtractionUsageResult = Struct.new(
    :allowed,
    :within_quota,
    :overage,
    :usage_position,
    :overage_position,
    :overage_cents,
    :extraction_period_start,
    keyword_init: true
  ) do
    def allowed?
      allowed
    end

    def overage?
      overage
    end
  end

  def plan_contract_limit
    current_plan_limits[:contracts] || 10
  end

  def plan_extraction_limit
    current_plan_limits[:extractions] || 5
  end

  def plan_extraction_overage_cents
    current_plan_tier&.extraction_overage_cents.to_i
  end

  def plan_user_limit
    current_plan_limits[:users] || 1
  end

  def plan_audit_log_days
    current_plan_limits[:audit_log_days]
  end

  def audit_log_cutoff_date
    days = plan_audit_log_days
    days ? days.days.ago : nil
  end

  def active_contracts_count
    contracts.not_archived.count
  end

  def at_contract_limit?
    active_contracts_count >= plan_contract_limit
  end

  def at_extraction_limit?
    ai_extractions_count >= plan_extraction_limit
  end

  def at_user_limit?
    memberships.count >= plan_user_limit
  end

  def seats_used
    memberships.count
  end

  def seats_remaining
    limit = plan_user_limit
    return Float::INFINITY if limit == Float::INFINITY
    [ limit - seats_used, 0 ].max
  end

  def contracts_remaining
    limit = plan_contract_limit
    return Float::INFINITY if limit == Float::INFINITY
    [ limit - active_contracts_count, 0 ].max
  end

  def extractions_remaining
    limit = plan_extraction_limit
    return Float::INFINITY if limit == Float::INFINITY
    [ limit - ai_extractions_count, 0 ].max
  end

  def extraction_overage_count
    ai_extractions_overage_count.to_i
  end

  def estimated_extraction_overage_cents
    if respond_to?(:extraction_overage_charges) &&
       defined?(ExtractionOverageCharge) &&
       ExtractionOverageCharge.table_exists?
      ledger_total = extraction_overage_charges.where(extraction_period_start_at: extraction_period_start).sum(:overage_cents)
      return ledger_total if ledger_total.positive?
    end

    extraction_overage_count * plan_extraction_overage_cents
  end

  def near_contract_limit?(threshold = 2)
    limit = plan_contract_limit
    return false if limit == Float::INFINITY
    active_contracts_count >= (limit - threshold)
  end

  def near_extraction_limit?(threshold = 2)
    limit = plan_extraction_limit
    return false if limit == Float::INFINITY
    ai_extractions_count >= (limit - threshold)
  end

  def increment_extraction_count!
    consume_extraction_usage!.allowed?
  end

  def consume_extraction_usage!
    with_lock do
      reset_monthly_extractions_if_needed!
      period_start = extraction_period_start
      limit = plan_extraction_limit

      if limit == Float::INFINITY
        row = increment_usage_and_overage_returning!(limit: nil, overage_enabled: false)
        return build_usage_result(
          allowed: true,
          within_quota: true,
          overage: false,
          usage_position: row["ai_extractions_count"].to_i,
          overage_position: 0,
          overage_cents: 0,
          extraction_period_start: period_start
        )
      end

      if extraction_overage_enabled?
        row = increment_usage_and_overage_returning!(limit:, overage_enabled: true)
        usage_position = row["ai_extractions_count"].to_i
        overage_position = row["ai_extractions_overage_count"].to_i
        overage = usage_position > limit

        return build_usage_result(
          allowed: true,
          within_quota: !overage,
          overage:,
          usage_position:,
          overage_position: overage ? overage_position : 0,
          overage_cents: overage ? plan_extraction_overage_cents : 0,
          extraction_period_start: period_start
        )
      end

      row = increment_with_limit_returning!(limit)
      return build_usage_result(allowed: false, extraction_period_start: period_start) if row.blank?

      build_usage_result(
        allowed: true,
        within_quota: true,
        overage: false,
        usage_position: row["ai_extractions_count"].to_i,
        overage_position: 0,
        overage_cents: 0,
        extraction_period_start: period_start
      )
    end
  end

  def reset_monthly_extractions!
    update!(
      ai_extractions_count: 0,
      ai_extractions_overage_count: 0,
      ai_extractions_reset_at: Time.current
    )
  end

  def plan_display_name
    PlanCatalogService.plan_display_name(plan)
  end

  def free_plan?
    plan == PlanCatalogService.default_plan_slug
  end

  def paid_plan?
    PlanCatalogService.paid_plan_slug?(plan)
  end

  def extraction_overage_enabled?
    return false unless paid_plan?

    limit = plan_extraction_limit
    return false if limit == Float::INFINITY
    return false unless plan_extraction_overage_cents.positive?

    return false unless respond_to?(:active_subscription)
    subscription = active_subscription
    return false unless subscription
    return false if pending_cancellation?

    subscription.status.to_s.in?(%w[active trialing])
  end

  def extraction_period_start
    sub = active_subscription if respond_to?(:active_subscription)
    anchor_time = sub&.current_period_start

    if anchor_time.present?
      anchor_day = anchor_time.day
      today = Time.current
      # Use the subscription's anchor day within the current month, clamped for short months
      period_start = today.change(day: [ anchor_day, today.end_of_month.day ].min).beginning_of_day
      # If that date is still in the future, roll back one month
      period_start = (period_start - 1.month).change(day: [ anchor_day, (period_start - 1.month).end_of_month.day ].min).beginning_of_day if period_start > today
      period_start
    else
      Time.current.beginning_of_month
    end
  end

  def extraction_period_end
    extraction_period_start + 1.month
  end

  def reset_monthly_extractions_if_needed!
    return if ai_extractions_reset_at.present? && ai_extractions_reset_at >= extraction_period_start

    reset_monthly_extractions!
  end

  def upgrade_from_current?(target_plan)
    hierarchy = PlanCatalogService.plan_hierarchy
    current_rank = hierarchy[plan] || 0
    target_rank = hierarchy[target_plan] || 0
    target_rank > current_rank
  end

  def downgrade_from_current?(target_plan)
    hierarchy = PlanCatalogService.plan_hierarchy
    current_rank = hierarchy[plan] || 0
    target_rank = hierarchy[target_plan] || 0
    target_rank < current_rank
  end

  def downgrade_eligibility(target_plan)
    unless PlanCatalogService.valid_plan_slug?(target_plan)
      return { eligible: false, blockers: [ "Unknown plan: #{target_plan}" ] }
    end

    target_limits = PlanCatalogService.plan_limits_for(target_plan)

    blockers = []

    contract_limit = target_limits[:contracts]
    if contract_limit != Float::INFINITY && active_contracts_count > contract_limit
      blockers << "You have #{active_contracts_count} active contracts but #{target_plan.titleize} allows #{contract_limit}. Archive or remove #{active_contracts_count - contract_limit} contracts first."
    end

    user_limit = target_limits[:users]
    if user_limit != Float::INFINITY && memberships.count > user_limit
      blockers << "You have #{memberships.count} team members but #{target_plan.titleize} allows #{user_limit}. Remove #{memberships.count - user_limit} members first."
    end

    { eligible: blockers.empty?, blockers: blockers }
  end

  def pending_downgrade?
    pending_plan.present?
  end

  def pending_cancellation?
    return false unless respond_to?(:pay_customers)

    pay_customers&.first&.subscriptions&.active&.where&.not(ends_at: nil)&.exists? || false
  end

  private

  def build_usage_result(
    allowed:,
    within_quota: false,
    overage: false,
    usage_position: nil,
    overage_position: nil,
    overage_cents: 0,
    extraction_period_start:
  )
    ExtractionUsageResult.new(
      allowed:,
      within_quota:,
      overage:,
      usage_position:,
      overage_position:,
      overage_cents:,
      extraction_period_start:
    )
  end

  def increment_usage_and_overage_returning!(limit:, overage_enabled:)
    table = self.class.quoted_table_name

    sql = if overage_enabled
      self.class.send(:sanitize_sql_array, [
        <<~SQL.squish, limit, id
          UPDATE #{table}
          SET ai_extractions_count = ai_extractions_count + 1,
              ai_extractions_overage_count = ai_extractions_overage_count + CASE
                WHEN ai_extractions_count + 1 > ? THEN 1
                ELSE 0
              END
          WHERE id = ?
          RETURNING ai_extractions_count, ai_extractions_overage_count
        SQL
      ])
    else
      self.class.send(:sanitize_sql_array, [
        <<~SQL.squish, id
          UPDATE #{table}
          SET ai_extractions_count = ai_extractions_count + 1
          WHERE id = ?
          RETURNING ai_extractions_count, ai_extractions_overage_count
        SQL
      ])
    end

    row = self.class.connection.select_one(sql)
    reload
    row
  end

  def increment_with_limit_returning!(limit)
    table = self.class.quoted_table_name
    sql = self.class.send(:sanitize_sql_array, [
      <<~SQL.squish, id, limit
        UPDATE #{table}
        SET ai_extractions_count = ai_extractions_count + 1
        WHERE id = ? AND ai_extractions_count < ?
        RETURNING ai_extractions_count
      SQL
    ])

    row = self.class.connection.select_one(sql)
    reload if row.present?
    row
  end

  def current_plan_tier
    @current_plan_tier ||= {}
    @current_plan_tier[plan] ||= PlanCatalogService.tier_for(plan)
  end

  def current_plan_limits
    @current_plan_limits ||= {}
    @current_plan_limits[plan] ||= PlanCatalogService.plan_limits_for(plan)
  end
end
