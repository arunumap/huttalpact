require "test_helper"

class PricingControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @org = organizations(:one)
  end

  test "show renders pricing page when logged in" do
    get pricing_path
    assert_response :success
    assert_select "h2", text: /Simple, transparent pricing/
  end

  test "show renders pricing page when logged out" do
    sign_out
    get pricing_path
    assert_response :success
    assert_select "h2", text: /Simple, transparent pricing/
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
    # Should have the full-width pricing grid
    assert_select "div.max-w-5xl"
  end

  test "pricing page shows FAQ section" do
    get pricing_path
    assert_response :success
    assert_match "Frequently Asked Questions", response.body
    assert_match "Can I change plans later?", response.body
  end

  test "guest sees sign up links instead of upgrade buttons" do
    sign_out
    get pricing_path
    assert_response :success
    assert_match "Get Started", response.body
    assert_match "Sign In", response.body
    assert_match "Sign Up", response.body
  end
end
