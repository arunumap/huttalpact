require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
  end

  test "should get show" do
    get dashboard_path
    assert_response :success
  end

  test "redirects to login when not authenticated" do
    sign_out
    get dashboard_path
    assert_redirected_to new_session_path
  end

  test "displays summary stat cards" do
    get dashboard_path
    assert_response :success
    assert_select "dt", text: "Total Contracts"
    assert_select "dt", text: "Active"
    assert_select "dt", text: "Monthly Revenue"
    assert_select "dt", text: "Monthly Spend"
    assert_select "dt", text: "Expiring Soon"
  end

  test "displays correct contract counts" do
    get dashboard_path
    # Organization one has: hvac_maintenance (active), landscaping (expiring_soon), expired_insurance (expired)
    assert_select "dd span.text-3xl", text: "3" # total
  end

  test "displays quick-add contract button in header" do
    get dashboard_path
    assert_select "a[href='#{new_contract_path}']", text: /Add Contract/
  end

  test "displays upcoming renewals section" do
    get dashboard_path
    assert_select "h3", text: "Upcoming Renewals"
  end

  test "displays renewal with days countdown" do
    contract = contracts(:hvac_maintenance)
    contract.update!(next_renewal_date: 25.days.from_now.to_date)

    get dashboard_path
    assert_select "table a[href='#{contract_path(contract)}']", text: contract.title
  end

  test "displays 30/60/90 day renewal tabs" do
    get dashboard_path
    assert_select "button", text: /30 days/
    assert_select "button", text: /60 days/
    assert_select "button", text: /90 days/
  end

  test "displays expiring contracts section when contracts expiring" do
    get dashboard_path
    # landscaping has end_date ~15 days from now with status expiring_soon
    assert_select "h3", text: "Expiring Contracts"
  end

  test "displays status overview" do
    get dashboard_path
    assert_select "h3", text: "Status Overview"
  end

  test "displays monthly revenue by type" do
    get dashboard_path
    assert_select "h3", text: "Monthly Revenue by Type"
  end

  test "displays monthly spend by type" do
    get dashboard_path
    assert_select "h3", text: "Monthly Spend by Type"
  end

  test "displays top vendors by value" do
    get dashboard_path
    assert_select "h3", text: "Top Vendors by Value"
    assert_select "span", text: "CoolAir Services"
  end

  test "displays net monthly cash flow" do
    get dashboard_path
    assert_select "h3", text: "Net Monthly Cash Flow"
  end

  test "displays recently added section" do
    get dashboard_path
    assert_select "h3", text: "Recently Added"
  end

  test "shows monthly spend for outbound contracts" do
    get dashboard_path
    # hvac_maintenance is active+outbound ($1,200/mo)
    assert_select "dt", text: "Monthly Spend"
    assert_select "span", text: /\$1,200\.00/
  end

  test "shows plan info in total contracts card" do
    get dashboard_path
    assert_select "span", text: /on Free plan/
  end

  test "does not show other organization contracts" do
    get dashboard_path
    # other_org_contract belongs to organization :two
    assert_select "a", text: contracts(:other_org_contract).title, count: 0
  end

  test "shows direction badges in recently added" do
    get dashboard_path
    assert_select "span", text: "Revenue"  # landscaping is inbound
    assert_select "span", text: "Expense"  # hvac_maintenance & expired_insurance are outbound
  end

  test "shows net cash flow with revenue and spend" do
    get dashboard_path
    assert_select "span", text: "Revenue (inbound)"
    assert_select "span", text: "Spend (outbound)"
    assert_select "span", text: "Net"
  end
end
