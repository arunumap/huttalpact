require "test_helper"

class PlanCatalogServiceTest < ActiveSupport::TestCase
  setup do
    @free_tier = plan_tiers(:free)
    @starter_tier = plan_tiers(:starter)
    @pro_tier = plan_tiers(:pro)
  end

  test "plan_limits_for returns database-backed limits" do
    free_limits = PlanCatalogService.plan_limits_for(@free_tier.slug)
    pro_limits = PlanCatalogService.plan_limits_for(@pro_tier.slug)

    assert_equal 10, free_limits[:contracts]
    assert_equal 5, free_limits[:extractions]
    assert_equal 1, free_limits[:users]
    assert_equal 7, free_limits[:audit_log_days]

    assert_equal Float::INFINITY, pro_limits[:contracts]
    assert_equal Float::INFINITY, pro_limits[:extractions]
    assert_equal Float::INFINITY, pro_limits[:users]
    assert_nil pro_limits[:audit_log_days]
  end

  test "lookup key resolution and interval parsing" do
    assert_equal @starter_tier.slug, PlanCatalogService.plan_for_lookup_key(@starter_tier.monthly_lookup_key)
    assert_equal @starter_tier.slug, PlanCatalogService.plan_for_lookup_key(@starter_tier.annual_lookup_key)
    assert_equal "monthly", PlanCatalogService.interval_for_lookup_key(@starter_tier.monthly_lookup_key)
    assert_equal "annual", PlanCatalogService.interval_for_lookup_key(@starter_tier.annual_lookup_key)
    assert_nil PlanCatalogService.interval_for_lookup_key("unknown_lookup_key")
  end

  test "active_tiers_for_pricing filters inactive and hidden tiers" do
    hidden_tier = create_plan_tier(
      slug: "hidden-tier",
      name: "Hidden Tier",
      rank: 20,
      position: 20,
      visible_on_pricing_page: false,
      monthly_lookup_key: "hidden_monthly",
      annual_lookup_key: "hidden_annual"
    )

    inactive_tier = create_plan_tier(
      slug: "inactive-tier",
      name: "Inactive Tier",
      rank: 21,
      position: 21,
      active: false,
      monthly_lookup_key: "inactive_monthly",
      annual_lookup_key: "inactive_annual"
    )

    tier_slugs = PlanCatalogService.active_tiers_for_pricing.map(&:slug)

    assert_includes tier_slugs, @free_tier.slug
    assert_includes tier_slugs, @starter_tier.slug
    assert_not_includes tier_slugs, hidden_tier.slug
    assert_not_includes tier_slugs, inactive_tier.slug
  end

  test "default_plan_slug resolves to default tier" do
    assert_equal @free_tier.slug, PlanCatalogService.default_plan_slug
  end

  test "paid_plan_slug uses tier pricing in database mode" do
    assert_not PlanCatalogService.paid_plan_slug?(@free_tier.slug)
    assert PlanCatalogService.paid_plan_slug?(@starter_tier.slug)
    assert PlanCatalogService.paid_plan_slug?(@pro_tier.slug)
  end

  test "fallback mode returns default catalog values" do
    PlanCatalogService.stub(:plan_tiers_available?, false) do
      assert_equal "free", PlanCatalogService.default_plan_slug
      assert_equal "starter", PlanCatalogService.plan_for_lookup_key("starter_monthly")
      assert_equal "pro", PlanCatalogService.plan_for_lookup_key("pro_annual")
      assert_equal %w[free starter pro], PlanCatalogService.available_plan_slugs

      fallback_limits = PlanCatalogService.plan_limits_for("free")
      assert_equal 10, fallback_limits[:contracts]
      assert_equal 5, fallback_limits[:extractions]
      assert_equal 1, fallback_limits[:users]

      assert PlanCatalogService.paid_plan_slug?("starter")
      assert PlanCatalogService.paid_plan_slug?("pro")
      assert_not PlanCatalogService.paid_plan_slug?("free")
    end
  end

  private

  def create_plan_tier(slug:, name:, rank:, position:, active: true, visible_on_pricing_page: true, monthly_lookup_key:, annual_lookup_key:)
    PlanTier.create!(
      slug: slug,
      name: name,
      description: "Test tier",
      rank: rank,
      position: position,
      contract_limit: 50,
      extraction_limit: 25,
      extraction_overage_cents: 0,
      user_limit: 5,
      monthly_price_cents: 5900,
      annual_price_cents: 59000,
      monthly_lookup_key: monthly_lookup_key,
      annual_lookup_key: annual_lookup_key,
      active: active,
      visible_on_pricing_page: visible_on_pricing_page,
      featured: false,
      system_tier: false,
      default_tier: false,
      feature_list: [ "Test feature" ]
    )
  end
end
