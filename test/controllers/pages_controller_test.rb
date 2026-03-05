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

  test "ads landing page preserves attribution params in inline signup form" do
    get ads_contracts_landing_path(utm_source: "google", utm_medium: "cpc", utm_campaign: "spring", gclid: "abc123")
    assert_response :success

    assert_select "form[action='#{registration_path}']" do
      assert_select "input[name='utm_source'][value='google']", count: 1
      assert_select "input[name='utm_medium'][value='cpc']", count: 1
      assert_select "input[name='utm_campaign'][value='spring']", count: 1
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
