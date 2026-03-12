require "test_helper"

class PricingControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @org = organizations(:one)
  end

  test "show renders pricing page when logged in" do
    get pricing_path
    assert_response :success
    assert_select "h1", text: /Simple, transparent pricing/
  end

  test "show renders pricing page when logged out" do
    sign_out
    get pricing_path
    assert_response :success
    assert_select "h1", text: /Simple, transparent pricing/
    assert_select "a[href='#{pricing_path}']", text: "Pricing"
    assert_select "a[href='#{solutions_path}']", text: "Solutions"
    assert_select "a[href='#{blog_path}']", text: "Blog"
  end

  test "show displays a card for each visible pricing tier" do
    get pricing_path

    PlanCatalogService.active_tiers_for_pricing.each do |tier|
      assert_select "h3", text: tier.name
    end
  end

  test "shows current plan badge for logged in user" do
    get pricing_path
    assert_response :success
    # User one's org is on free plan
    assert_match "Current Plan", response.body
  end

  test "non-owner sees contact message instead of upgrade buttons" do
    member_user = User.create!(email_address: "member_pricing@example.com", password: "password123", first_name: "Member", last_name: "Pricing", terms_accepted: "1")
    org = users(:one).memberships.first.organization
    Membership.create!(user: member_user, organization: org, role: Membership::MEMBER_ROLE)
    sign_out
    sign_in_as member_user

    get pricing_path
    assert_response :success
    assert_match "Contact your organization owner to upgrade", response.body

    upgradeable_tiers = PlanCatalogService.active_tiers_for_pricing.select do |tier|
      tier.monthly_lookup_key.present? && !tier.free?
    end

    upgradeable_tiers.each do |tier|
      assert_no_match(/Upgrade to #{Regexp.escape(tier.name)}/, response.body)
    end
  end

  test "owner sees upgrade buttons" do
    get pricing_path
    assert_response :success

    upgradeable_tiers = PlanCatalogService.active_tiers_for_pricing.select do |tier|
      tier.monthly_lookup_key.present? && !tier.free? && tier.slug != @org.plan
    end

    upgradeable_tiers.each do |tier|
      assert_match "Upgrade to #{tier.name}", response.body
    end
  end

  test "pricing page uses pricing layout not auth layout" do
    get pricing_path
    assert_response :success

    tier_count = PlanCatalogService.active_tiers_for_pricing.size
    expected_container_class = tier_count > 3 ? "max-w-7xl" : "max-w-5xl"

    assert_select "div.#{expected_container_class}"
    if tier_count > 3
      assert_match(/sm:grid-cols-2/, response.body)
      assert_match(/xl:grid-cols-4/, response.body)
    else
      assert_match(/sm:grid-cols-3/, response.body)
    end
  end

  test "pricing page includes annual toggle wiring hooks" do
    get pricing_path
    assert_response :success

    tiers = PlanCatalogService.active_tiers_for_pricing
    annual_priced_tier_count = tiers.count { |tier| tier.annual_price_cents.to_i.positive? }

    assert_select "div[data-controller~='pricing-toggle']", 1
    assert_select "button[data-action='click->pricing-toggle#selectMonthly'][data-pricing-toggle-target='monthlyBtn']", 1
    assert_select "button[data-action='click->pricing-toggle#selectAnnual'][data-pricing-toggle-target='annualBtn']", 1
    assert_select "div[data-pricing-toggle-target='planCard'][data-pricing-toggle-monthly-price][data-pricing-toggle-annual-price]", tiers.size
    assert_select "[data-pricing-toggle-role='annual-total']", annual_priced_tier_count
  end

  test "pricing page shows FAQ section" do
    get pricing_path
    assert_response :success
    assert_match "Frequently asked questions", response.body
    assert_match "Can I change plans later?", response.body
  end

  test "pricing page shows overage copy when tier has extraction overage price" do
    plan_tiers(:starter).update!(extraction_overage_cents: 125)

    get pricing_path
    assert_response :success
    assert_match "After included extractions:", response.body
    assert_match "$1.25/extraction", response.body
  end

  test "guest sees sign up links instead of upgrade buttons" do
    sign_out
    get pricing_path
    assert_response :success
    assert_match "Get Started", response.body
    assert_match "Sign In", response.body
    assert_match "Start Free", response.body
  end

  test "guest free tier uses non-highlight card style" do
    sign_out
    get pricing_path
    assert_response :success

    assert_select "div.ring-2.ring-amber-500 h3", text: "Free", count: 0
    assert_select "div.ring-1.ring-gray-200 h3", text: "Free", count: 1
  end
end
