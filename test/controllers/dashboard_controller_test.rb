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

  test "displays extraction billing snapshot" do
    get dashboard_path
    assert_response :success

    assert_select "#extraction-billing-snapshot" do
      assert_select "h3", text: "AI Extraction Billing Snapshot"
      assert_select "dt", text: "Extractions used"
      assert_select "dd", text: "0 / 5"
      assert_select "dt", text: "Overage price"
      assert_select "dd", text: "Not available"
      assert_select "dt", text: "Estimated bill"
      assert_select "dd", text: "$0.00"
    end
  end

  test "estimated bill includes base plan and accrued overage charges" do
    plan_tiers(:starter).update!(extraction_overage_cents: 50)
    organizations(:one).update!(plan: "starter", ai_extractions_count: 52, ai_extractions_overage_count: 2)
    create_active_subscription_for(organizations(:one), current_period_start: 10.days.ago, current_period_end: 20.days.from_now)

    get dashboard_path
    assert_response :success

    assert_select "#extraction-billing-snapshot" do
      assert_select "dd", text: "$0.50"
      assert_select "dd", text: "$50.00"
    end
  end

  test "shows 80 percent extraction usage warning" do
    organizations(:one).update!(plan: "starter", ai_extractions_count: 40, ai_extractions_overage_count: 0)

    get dashboard_path
    assert_response :success
    assert_includes response.body, "You've used 80% of your AI extractions for this billing period."
  end

  test "shows upgrade nudge when higher tier lowers overage cost" do
    plan_tiers(:starter).update!(extraction_overage_cents: 50)
    plan_tiers(:pro).update!(extraction_limit: 500, extraction_overage_cents: 40)
    organizations(:one).update!(plan: "starter", ai_extractions_count: 40, ai_extractions_overage_count: 0)

    get dashboard_path
    assert_response :success
    assert_includes response.body, "Upgrade to Pro and lower extraction overage cost by 20%."
  end

  test "does not show upgrade nudge for unlimited extraction tier even if misconfigured overage exists" do
    plan_tiers(:starter).update!(extraction_overage_cents: 50)
    plan_tiers(:pro).update!(extraction_limit: nil, extraction_overage_cents: 40)
    organizations(:one).update!(plan: "starter", ai_extractions_count: 40, ai_extractions_overage_count: 0)

    get dashboard_path
    assert_response :success
    assert_not_includes response.body, "Upgrade to Pro and lower extraction overage cost by"
  end

  test "displays correct contract counts" do
    get dashboard_path
    # Organization one has: hvac_maintenance (active), landscaping (expiring_soon), expired_insurance (expired), commercial_lease (active)
    assert_select "dd span.text-3xl", text: "4" # total
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

  # --- Lease Insights tests (QA #3) ---

  test "displays Lease Insights section when lease contracts exist" do
    # commercial_lease fixture is a lease contract in org :one
    get dashboard_path
    assert_response :success
    assert_select "h2", text: "Lease Insights"
  end

  test "displays Option Deadlines widget" do
    get dashboard_path
    assert_select "h3", text: "Option Deadlines"
  end

  test "displays Upcoming Rent Changes widget" do
    get dashboard_path
    assert_select "h3", text: "Upcoming Rent Changes"
  end

  test "displays TI Deadlines widget" do
    get dashboard_path
    assert_select "h3", text: "TI Deadlines"
  end

  test "displays Lease Milestones widget" do
    get dashboard_path
    assert_select "h3", text: "Lease Milestones"
  end

  test "shows option with upcoming notice deadline" do
    # termination_option has notice_deadline ~90 days from now
    get dashboard_path
    assert_select "span", text: /Termination/i
  end

  test "shows upcoming rent escalation" do
    # future_cpi escalation is ~2 years from now (within 12 months check fails)
    # Create one within range
    contracts(:commercial_lease).rent_escalations.create!(
      effective_date: 3.months.from_now.to_date,
      base_rent_monthly: 9200,
      base_rent_annual: 110400,
      escalation_type: "fixed_percentage",
      escalation_value: 3.0,
      description: "Mid-term adjustment",
      position: 10
    )
    get dashboard_path
    # escalation_description returns "3.0% increase" for fixed_percentage type
    assert_select "span", text: /3\.0% increase/
  end

  test "shows upcoming milestone" do
    # insurance_renewal milestone is 45 days from now (within 90 day range)
    get dashboard_path
    assert_select "span", text: /Insurance Renewal/i
  end

  test "does not display Lease Insights when no lease contracts" do
    # Remove all lease contracts from org :one
    Contract.where(contract_type: "lease").update_all(contract_type: "service_agreement")
    get dashboard_path
    assert_response :success
    assert_select "h2", text: "Lease Insights", count: 0
  end

  private

  def create_active_subscription_for(org, current_period_start:, current_period_end:)
    customer = org.set_payment_processor(:stripe)
    customer.update!(processor_id: "cus_dashboard_#{SecureRandom.hex(4)}")

    Pay::Stripe::Subscription.create!(
      customer: customer,
      processor_id: "sub_dashboard_#{SecureRandom.hex(4)}",
      processor_plan: "price_dashboard_monthly",
      name: "default",
      status: "active",
      current_period_start: current_period_start,
      current_period_end: current_period_end
    )
  end
end
