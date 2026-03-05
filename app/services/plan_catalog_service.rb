class PlanCatalogService
  FallbackTier = Struct.new(
    :slug,
    :name,
    :description,
    :rank,
    :position,
    :contract_limit,
    :extraction_limit,
    :extraction_overage_cents,
    :user_limit,
    :audit_log_days,
    :monthly_price_cents,
    :annual_price_cents,
    :monthly_lookup_key,
    :annual_lookup_key,
    :active,
    :visible_on_pricing_page,
    :featured,
    :system_tier,
    :default_tier,
    :feature_list,
    keyword_init: true
  ) do
    def paid?
      monthly_price_cents.to_i.positive? || annual_price_cents.to_i.positive?
    end

    def free?
      !paid?
    end

    def active?
      !!active
    end

    def visible_on_pricing_page?
      !!visible_on_pricing_page
    end

    def featured?
      !!featured
    end

    def default_tier?
      !!default_tier
    end

    def system_tier?
      !!system_tier
    end
  end

  DEFAULT_PLAN_LIMITS = {
    "free" => { contracts: 10, extractions: 5, users: 1, audit_log_days: 7 },
    "starter" => { contracts: 100, extractions: 50, users: 5, audit_log_days: 30 },
    "pro" => { contracts: Float::INFINITY, extractions: Float::INFINITY, users: Float::INFINITY, audit_log_days: nil }
  }.freeze

  DEFAULT_LOOKUP_KEYS = {
    "starter_monthly" => "starter",
    "starter_annual" => "starter",
    "pro_monthly" => "pro",
    "pro_annual" => "pro"
  }.freeze

  DEFAULT_PLAN_HIERARCHY = { "free" => 0, "starter" => 1, "pro" => 2 }.freeze
  DEFAULT_PLAN_SLUG = "free".freeze

  DEFAULT_TIER_DATA = [
    {
      slug: "free",
      name: "Free",
      description: "Get started with the basics.",
      rank: 0,
      position: 0,
      contract_limit: 10,
      extraction_limit: 5,
      extraction_overage_cents: 0,
      user_limit: 1,
      audit_log_days: 7,
      monthly_price_cents: 0,
      annual_price_cents: 0,
      monthly_lookup_key: nil,
      annual_lookup_key: nil,
      active: true,
      visible_on_pricing_page: true,
      featured: false,
      system_tier: true,
      default_tier: true,
      feature_list: [
        "Up to 10 contracts",
        "5 AI extractions per billing period",
        "1 user",
        "7-day activity log"
      ]
    },
    {
      slug: "starter",
      name: "Starter",
      description: "Smart contract tracking for growing businesses.",
      rank: 1,
      position: 1,
      contract_limit: 100,
      extraction_limit: 50,
      extraction_overage_cents: 0,
      user_limit: 5,
      audit_log_days: 30,
      monthly_price_cents: 4900,
      annual_price_cents: 49200,
      monthly_lookup_key: "starter_monthly",
      annual_lookup_key: "starter_annual",
      active: true,
      visible_on_pricing_page: true,
      featured: true,
      system_tier: false,
      default_tier: false,
      feature_list: [
        "Up to 100 contracts",
        "50 AI extractions per billing period",
        "Up to 5 team members",
        "30-day activity log"
      ]
    },
    {
      slug: "pro",
      name: "Pro",
      description: "Unlimited contract tracking for teams of any size.",
      rank: 2,
      position: 2,
      contract_limit: nil,
      extraction_limit: nil,
      extraction_overage_cents: 0,
      user_limit: nil,
      audit_log_days: nil,
      monthly_price_cents: 14900,
      annual_price_cents: 149000,
      monthly_lookup_key: "pro_monthly",
      annual_lookup_key: "pro_annual",
      active: true,
      visible_on_pricing_page: true,
      featured: false,
      system_tier: false,
      default_tier: false,
      feature_list: [
        "Unlimited contracts",
        "Unlimited AI extractions",
        "Unlimited users",
        "Full activity history"
      ]
    }
  ].freeze

  class << self
    def plan_limits_for(plan_slug)
      tier = tier_for(plan_slug)
      return fallback_limits_for(plan_slug) unless tier

      {
        contracts: tier.contract_limit || Float::INFINITY,
        extractions: tier.extraction_limit || Float::INFINITY,
        users: tier.user_limit || Float::INFINITY,
        audit_log_days: tier.audit_log_days
      }
    end

    def plan_hierarchy
      tiers = available_tiers
      return DEFAULT_PLAN_HIERARCHY if tiers.empty?

      tiers.each_with_object({}) { |tier, map| map[tier.slug] = tier.rank }
    end

    def lookup_keys
      tiers = available_tiers
      return DEFAULT_LOOKUP_KEYS if tiers.empty?

      map = {}
      tiers.each do |tier|
        map[tier.monthly_lookup_key] = tier.slug if tier.monthly_lookup_key.present?
        map[tier.annual_lookup_key] = tier.slug if tier.annual_lookup_key.present?
      end

      map.presence || DEFAULT_LOOKUP_KEYS
    end

    def plan_for_lookup_key(lookup_key)
      return nil if lookup_key.blank?

      lookup_keys[lookup_key]
    end

    def valid_lookup_key?(lookup_key)
      plan_for_lookup_key(lookup_key).present?
    end

    def interval_for_lookup_key(lookup_key)
      return nil unless valid_lookup_key?(lookup_key)

      return "annual" if lookup_key.to_s.end_with?("_annual")
      return "monthly" if lookup_key.to_s.end_with?("_monthly")

      nil
    end

    def tier_for(plan_slug)
      return nil if plan_slug.blank?
      return nil unless plan_tiers_available?

      PlanTier.find_by(slug: plan_slug)
    end

    def plan_display_name(plan_slug)
      tier_for(plan_slug)&.name || plan_slug.to_s.titleize
    end

    def valid_plan_slug?(plan_slug)
      return false if plan_slug.blank?

      available_plan_slugs.include?(plan_slug)
    end

    def available_plan_slugs
      tiers = available_tiers
      return tiers.map(&:slug) unless tiers.empty?

      DEFAULT_PLAN_HIERARCHY.keys
    end

    def active_tiers_for_pricing
      available_tiers.select(&:active?).select(&:visible_on_pricing_page?)
    end

    def active_tiers_for_billing
      available_tiers.select(&:active?)
    end

    def default_plan_slug
      return DEFAULT_PLAN_SLUG unless plan_tiers_available?

      PlanTier.find_by(default_tier: true)&.slug ||
        PlanTier.find_by(slug: DEFAULT_PLAN_SLUG)&.slug ||
        PlanTier.ordered.first&.slug ||
        DEFAULT_PLAN_SLUG
    rescue ActiveRecord::StatementInvalid
      DEFAULT_PLAN_SLUG
    end

    def paid_plan_slug?(plan_slug)
      return false if plan_slug.blank?

      tier = tier_for(plan_slug)
      return false unless tier || available_plan_slugs.include?(plan_slug)
      return !plan_slug.eql?(default_plan_slug) unless tier

      tier.paid?
    end

    def plan_tiers_available?
      defined?(PlanTier) && PlanTier.table_exists?
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
      false
    end

    def available_tiers
      if plan_tiers_available?
        tiers = PlanTier.ordered.to_a
        return tiers if tiers.any?
      end

      fallback_tiers
    rescue ActiveRecord::StatementInvalid
      fallback_tiers
    end

    private

    def fallback_limits_for(plan_slug)
      DEFAULT_PLAN_LIMITS[plan_slug] || DEFAULT_PLAN_LIMITS[default_plan_slug] || DEFAULT_PLAN_LIMITS[DEFAULT_PLAN_SLUG]
    end

    def fallback_tiers
      DEFAULT_TIER_DATA.map { |attrs| FallbackTier.new(**attrs) }
    end
  end
end
