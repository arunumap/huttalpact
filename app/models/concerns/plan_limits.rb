module PlanLimits
  extend ActiveSupport::Concern

  PLAN_LIMITS = {
    "free" => { contracts: 10, extractions: 5, users: 1, audit_log_days: 7 },
    "starter" => { contracts: 100, extractions: 50, users: 5, audit_log_days: 30 },
    "pro" => { contracts: Float::INFINITY, extractions: Float::INFINITY, users: Float::INFINITY, audit_log_days: nil }
  }.freeze

  STRIPE_PRICES = {
    "starter_monthly" => ENV.fetch("STRIPE_STARTER_MONTHLY_PRICE_ID", "price_starter_monthly"),
    "starter_annual"  => ENV.fetch("STRIPE_STARTER_ANNUAL_PRICE_ID", "price_starter_annual"),
    "pro_monthly"     => ENV.fetch("STRIPE_PRO_MONTHLY_PRICE_ID", "price_pro_monthly"),
    "pro_annual"      => ENV.fetch("STRIPE_PRO_ANNUAL_PRICE_ID", "price_pro_annual")
  }.freeze

  PRICE_TO_PLAN = STRIPE_PRICES.each_with_object({}) { |(key, price_id), hash|
    hash[price_id] = key.split("_").first
  }.freeze

  def plan_contract_limit
    PLAN_LIMITS.dig(plan, :contracts) || 10
  end

  def plan_extraction_limit
    PLAN_LIMITS.dig(plan, :extractions) || 5
  end

  def plan_user_limit
    PLAN_LIMITS.dig(plan, :users) || 1
  end

  def plan_audit_log_days
    PLAN_LIMITS.dig(plan, :audit_log_days)
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
    plan.titleize
  end

  def free_plan?
    plan == "free"
  end

  def paid_plan?
    plan.in?(%w[starter pro])
  end

  def reset_monthly_extractions_if_needed!
    return if ai_extractions_reset_at.present? && ai_extractions_reset_at >= Time.current.beginning_of_month

    reset_monthly_extractions!
  end
end
