module PlanLimits
  extend ActiveSupport::Concern

  PLAN_LIMITS = {
    "free" => { contracts: 10, extractions: 5, users: 1, audit_log_days: 7 },
    "starter" => { contracts: 100, extractions: 50, users: 5, audit_log_days: 30 },
    "pro" => { contracts: Float::INFINITY, extractions: Float::INFINITY, users: Float::INFINITY, audit_log_days: nil }
  }.freeze

  LOOKUP_KEYS = {
    "starter_monthly" => "starter",
    "starter_annual"  => "starter",
    "pro_monthly"     => "pro",
    "pro_annual"      => "pro"
  }.freeze

  PLAN_HIERARCHY = { "free" => 0, "starter" => 1, "pro" => 2 }.freeze

  def plan_contract_limit
    current_plan_limits[:contracts] || 10
  end

  def plan_extraction_limit
    current_plan_limits[:extractions] || 5
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
    reset_monthly_extractions_if_needed!

    limit = plan_extraction_limit
    if limit == Float::INFINITY
      increment!(:ai_extractions_count)
      true
    else
      rows = self.class.where(id: id)
        .where("ai_extractions_count < ?", limit)
        .update_all("ai_extractions_count = ai_extractions_count + 1")
      reload if rows > 0
      rows > 0
    end
  end

  def reset_monthly_extractions!
    update!(ai_extractions_count: 0, ai_extractions_reset_at: Time.current)
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

  def reset_monthly_extractions_if_needed!
    return if ai_extractions_reset_at.present? && ai_extractions_reset_at >= Time.current.beginning_of_month

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

  def current_plan_limits
    @current_plan_limits ||= {}
    @current_plan_limits[plan] ||= PlanCatalogService.plan_limits_for(plan)
  end
end
