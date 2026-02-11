require "test_helper"

class PricingControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
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

  test "show displays three plan cards" do
    get pricing_path
    assert_select "h3", text: "Free"
    assert_select "h3", text: "Starter"
    assert_select "h3", text: "Pro"
  end

  test "shows current plan badge for logged in user" do
    get pricing_path
    assert_response :success
    # User one's org is on free plan
    assert_match "Current Plan", response.body
  end

  test "non-owner sees contact message instead of upgrade buttons" do
    member_user = User.create!(email_address: "member_pricing@example.com", password: "password123", first_name: "Member", last_name: "Pricing")
    org = users(:one).memberships.first.organization
    Membership.create!(user: member_user, organization: org, role: Membership::MEMBER_ROLE)
    sign_out
    sign_in_as member_user

    get pricing_path
    assert_response :success
    assert_match "Contact your organization owner to upgrade", response.body
    assert_no_match(/Upgrade to Starter/, response.body)
    assert_no_match(/Upgrade to Pro/, response.body)
  end

  test "owner sees upgrade buttons" do
    get pricing_path
    assert_response :success
    # Owner should see upgrade buttons for non-current plans
    assert_match "Upgrade to Starter", response.body
    assert_match "Upgrade to Pro", response.body
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
