require "test_helper"

class Admin::PlanTiersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin_user = admin_users(:one)
    @free_tier = plan_tiers(:free)
    @starter_tier = plan_tiers(:starter)
    @pro_tier = plan_tiers(:pro)
  end

  test "requires admin authentication" do
    get admin_plan_tiers_path
    assert_redirected_to new_admin_session_path
  end

  test "index renders for admin" do
    sign_in_as_admin(@admin_user)

    get admin_plan_tiers_path

    assert_response :success
    assert_match @free_tier.name, response.body
    assert_match @starter_tier.name, response.body
    assert_match @pro_tier.name, response.body
  end

  test "create plan tier parses feature list" do
    sign_in_as_admin(@admin_user)

    assert_difference "PlanTier.count", 1 do
      post admin_plan_tiers_path, params: {
        plan_tier: {
          slug: "growth",
          name: "Growth",
          description: "For scaling teams",
          rank: 10,
          position: 10,
          contract_limit: 500,
          extraction_limit: 200,
          extraction_overage_cents: 125,
          user_limit: 25,
          audit_log_days: 90,
          monthly_price_cents: 9900,
          annual_price_cents: 99000,
          monthly_lookup_key: "growth_monthly",
          annual_lookup_key: "growth_annual",
          active: true,
          visible_on_pricing_page: true,
          featured: false,
          system_tier: false,
          default_tier: false,
          feature_list_text: "Feature A\nFeature B"
        }
      }
    end

    tier = PlanTier.find_by!(slug: "growth")
    assert_equal [ "Feature A", "Feature B" ], tier.feature_list
    assert_equal 125, tier.extraction_overage_cents
    assert_redirected_to admin_plan_tier_path(tier)
  end

  test "update plan tier updates attributes and features" do
    sign_in_as_admin(@admin_user)

    patch admin_plan_tier_path(@pro_tier), params: {
      plan_tier: {
        name: "Pro Plus",
        monthly_price_cents: 19900,
        annual_price_cents: 199000,
        extraction_overage_cents: 225,
        feature_list_text: "Unlimited contracts\nUnlimited users"
      }
    }

    assert_redirected_to admin_plan_tier_path(@pro_tier)
    @pro_tier.reload
    assert_equal "Pro Plus", @pro_tier.name
    assert_equal 19900, @pro_tier.monthly_price_cents
    assert_equal 225, @pro_tier.extraction_overage_cents
    assert_equal [ "Unlimited contracts", "Unlimited users" ], @pro_tier.feature_list
  end

  test "deactivate blocks protected tier" do
    sign_in_as_admin(@admin_user)

    post deactivate_admin_plan_tier_path(@free_tier)

    assert_redirected_to admin_plan_tier_path(@free_tier)
    assert_match "cannot be deactivated", flash[:alert]
    assert @free_tier.reload.active?
  end

  test "deactivate blocks in-use tier" do
    sign_in_as_admin(@admin_user)

    post deactivate_admin_plan_tier_path(@starter_tier)

    assert_redirected_to admin_plan_tier_path(@starter_tier)
    assert_match "currently used", flash[:alert]
    assert @starter_tier.reload.active?
  end

  test "deactivate succeeds for unused tier" do
    sign_in_as_admin(@admin_user)
    tier = create_unused_tier

    post deactivate_admin_plan_tier_path(tier)

    assert_redirected_to admin_plan_tier_path(tier)
    assert_equal "Plan tier deactivated.", flash[:notice]
    assert_not tier.reload.active?
  end

  test "destroy blocks protected tier" do
    sign_in_as_admin(@admin_user)

    assert_no_difference "PlanTier.count" do
      delete admin_plan_tier_path(@free_tier)
    end

    assert_redirected_to admin_plan_tier_path(@free_tier)
    assert_match "cannot be deleted", flash[:alert]
  end

  test "destroy blocks in-use tier" do
    sign_in_as_admin(@admin_user)

    assert_no_difference "PlanTier.count" do
      delete admin_plan_tier_path(@starter_tier)
    end

    assert_redirected_to admin_plan_tier_path(@starter_tier)
    assert_match "currently used", flash[:alert]
  end

  test "destroy succeeds for unused tier" do
    sign_in_as_admin(@admin_user)
    tier = create_unused_tier

    assert_difference "PlanTier.count", -1 do
      delete admin_plan_tier_path(tier)
    end

    assert_redirected_to admin_plan_tiers_path
    assert_equal "Plan tier deleted.", flash[:notice]
  end

  test "sync_to_stripe success includes created and skipped" do
    sign_in_as_admin(@admin_user)

    result = { success: true, created: [ "pro_monthly" ], skipped: [ "pro_annual" ] }
    StripeAdminService.stub(:sync_plan_tier!, result) do
      post sync_to_stripe_admin_plan_tier_path(@pro_tier)
    end

    assert_redirected_to admin_plan_tier_path(@pro_tier)
    assert_match "Stripe sync complete", flash[:notice]
    assert_match "Created: pro_monthly", flash[:notice]
    assert_match "Skipped: pro_annual", flash[:notice]
  end

  test "sync_to_stripe failure shows alert" do
    sign_in_as_admin(@admin_user)

    result = { success: false, message: "Stripe unavailable" }
    StripeAdminService.stub(:sync_plan_tier!, result) do
      post sync_to_stripe_admin_plan_tier_path(@pro_tier)
    end

    assert_redirected_to admin_plan_tier_path(@pro_tier)
    assert_match "Stripe sync failed", flash[:alert]
  end

  private

  def create_unused_tier
    next_position = PlanTier.maximum(:position).to_i + 10
    next_rank = PlanTier.maximum(:rank).to_i + 10

    PlanTier.create!(
      slug: "unused-tier-#{next_position}",
      name: "Unused Tier",
      description: "Temporary test tier",
      rank: next_rank,
      position: next_position,
      contract_limit: 300,
      extraction_limit: 150,
      extraction_overage_cents: 0,
      user_limit: 20,
      monthly_price_cents: 8900,
      annual_price_cents: 89000,
      monthly_lookup_key: "unused_monthly_#{next_position}",
      annual_lookup_key: "unused_annual_#{next_position}",
      active: true,
      visible_on_pricing_page: true,
      featured: false,
      system_tier: false,
      default_tier: false,
      feature_list: [ "Temp feature" ]
    )
  end
end
