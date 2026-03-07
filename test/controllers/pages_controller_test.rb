require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "landing page is accessible to unauthenticated users" do
    get root_path
    assert_response :success
    assert_select "h1", /Smart contract tracking/
  end

  test "landing page shows signup and pricing CTAs" do
    get root_path
    assert_response :success
    assert_select "a[href='#{new_registration_path}']"
    assert_select "a[href='#{pricing_path}']"
  end

  test "landing page links to leases page" do
    get root_path
    assert_response :success
    assert_select "a[href='#{leases_path}']", text: "Leases"
  end

  test "authenticated user is redirected to dashboard" do
    sign_in_as(users(:one))
    get root_path
    assert_redirected_to dashboard_path
  end

  test "landing page has features section" do
    get root_path
    assert_response :success
    assert_select "h2", /Everything you need/
  end

  test "landing page has how-it-works section" do
    get root_path
    assert_response :success
    assert_select "h2", /Up and running in minutes/
  end

  test "landing page has pricing teaser" do
    get root_path
    assert_response :success
    assert_select "h2", /Simple, transparent pricing/
  end

  test "landing page pricing teaser renders dynamic tiers from plan catalog" do
    custom_tiers = [
      PlanCatalogService::FallbackTier.new(
        slug: "pilot",
        name: "Pilot",
        contract_limit: 25,
        extraction_limit: 15,
        user_limit: 2,
        monthly_price_cents: 5900,
        featured: false,
        active: true,
        visible_on_pricing_page: true
      ),
      PlanCatalogService::FallbackTier.new(
        slug: "growth_plus",
        name: "Growth Plus",
        contract_limit: nil,
        extraction_limit: nil,
        user_limit: nil,
        monthly_price_cents: 12900,
        featured: true,
        active: true,
        visible_on_pricing_page: true
      )
    ]

    PlanCatalogService.stub(:active_tiers_for_pricing, custom_tiers) do
      get root_path
    end

    assert_response :success
    assert_select "h3", text: "Pilot"
    assert_select "h3", text: "Growth Plus"
    assert_select "h3", text: "Starter", count: 0
    assert_match "$59", response.body
    assert_match "$129", response.body
  end

  test "ads landing page is accessible to unauthenticated users" do
    get ads_contracts_landing_path
    assert_response :success
    assert_select "h1", /Never miss a lease or vendor contract deadline again/
    assert_select "p", /For Property Managers/
  end

  test "ads landing page has inline signup form and noindex robots tag" do
    get ads_contracts_landing_path
    assert_response :success

    assert_select "form[action='#{registration_path}']"
    assert_select "input[name='user[first_name]']"
    assert_select "input[name='user[last_name]']"
    assert_select "input[name='user[organization_name]']"
    assert_select "input[name='user[email_address]']"
    assert_select "input[name='user[password]']"
    assert_select "input[name='user[password_confirmation]']"
    assert_select "input[name='source'][value='ads_contracts_landing']", count: 1
    assert_select "meta[name='robots'][content='noindex, nofollow']", count: 1
  end

  test "ads landing page shows first-week case study section" do
    get ads_contracts_landing_path
    assert_response :success

    assert_select "p", /What a typical first week looks like/i
    assert_select "h2", /How a 12-property management team got control of 87 contract deadlines/
    assert_select "h3", text: "The situation"
    assert_select "h3", text: "What happened"
    assert_select "h3", text: "The result"

    assert_not_includes response.body, "Trusted by Property Teams"
    assert_not_includes response.body, "Placeholder testimonials"
  end

  test "ads landing page applies dmm hero copy from utm_term" do
    get ads_contracts_landing_path(utm_term: "lease renewals")
    assert_response :success

    assert_select "h1", /Never miss critical lease renewals deadlines again/
    assert_select "p", /stay ahead of lease renewals deadlines/i
    assert_select "input[name='utm_term'][value='lease renewals']", count: 1
  end

  test "ads landing page falls back to default hero copy when utm_term is blank" do
    get ads_contracts_landing_path(utm_term: "   ")
    assert_response :success

    assert_select "h1", /Never miss a lease or vendor contract deadline again/
  end

  test "ads landing page preserves attribution params in inline signup form" do
    get ads_contracts_landing_path(utm_source: "google", utm_medium: "cpc", utm_campaign: "spring", utm_term: "lease tracking", gclid: "abc123")
    assert_response :success

    assert_select "form[action='#{registration_path}']" do
      assert_select "input[name='utm_source'][value='google']", count: 1
      assert_select "input[name='utm_medium'][value='cpc']", count: 1
      assert_select "input[name='utm_campaign'][value='spring']", count: 1
      assert_select "input[name='utm_term'][value='lease tracking']", count: 1
      assert_select "input[name='gclid'][value='abc123']", count: 1
      assert_select "input[name='source'][value='ads_contracts_landing']", count: 1
    end
  end

  test "home page does not reference ads landing page" do
    get root_path
    assert_response :success
    assert_not_includes response.body, ads_contracts_landing_path
  end

  test "leases page is accessible to unauthenticated users" do
    get leases_path
    assert_response :success
    assert_select "h1", /How we approach leases/
  end

  test "leases page highlights lease offerings and CTAs" do
    get leases_path
    assert_response :success
    assert_select "h2", /What we offer for leases/
    assert_select "a[href='#{new_registration_path}']"
    assert_select "a[href='#{pricing_path}']"
  end
end
