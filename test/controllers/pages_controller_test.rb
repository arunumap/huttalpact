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
