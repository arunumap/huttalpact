# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

if defined?(PlanTier) && PlanCatalogService.plan_tiers_available?
  tiers = [
    {
      slug: "free",
      name: "Free",
      description: "Get started with basic contract tracking.",
      rank: 0,
      position: 0,
      contract_limit: 10,
      extraction_limit: 5,
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
        "5 AI extractions/month",
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
        "50 AI extractions/month",
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
  ]

  tiers.each do |attributes|
    tier = PlanTier.find_or_initialize_by(slug: attributes[:slug])
    tier.assign_attributes(attributes)
    tier.save!
  end
end
