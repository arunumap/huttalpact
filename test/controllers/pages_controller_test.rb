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

  test "ads landing page is accessible to unauthenticated users" do
    get ads_contracts_landing_path
    assert_response :success
    assert_select "h1", /Stop missing contract deadlines/
  end

  test "ads landing page has signup CTA and noindex robots tag" do
    get ads_contracts_landing_path
    assert_response :success

    assert_select "a[href='#{new_registration_path(source: "ads_contracts_landing")}']", minimum: 2
    assert_select "meta[name='robots'][content='noindex, nofollow']", count: 1
  end

  test "ads landing page preserves attribution params in signup CTA links" do
    get ads_contracts_landing_path(utm_source: "google", utm_medium: "cpc", utm_campaign: "spring", gclid: "abc123")
    assert_response :success

    expected_signup_path = new_registration_path(
      utm_source: "google",
      utm_medium: "cpc",
      utm_campaign: "spring",
      gclid: "abc123",
      source: "ads_contracts_landing"
    )
    assert_select "a[href='#{expected_signup_path}']", minimum: 2
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
