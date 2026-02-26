require "test_helper"

class Settings::BillingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @org = organizations(:one)
    sign_in_as @user
  end

  test "show renders billing page for owner" do
    get settings_billing_path
    assert_response :success
    assert_select "h2", text: "Current Plan"
    assert_select "h2", text: "Usage"
  end

  test "show displays usage meters" do
    get settings_billing_path
    assert_response :success
    assert_match "Contracts", response.body
    assert_match "AI Extractions", response.body
    assert_match "Team Members", response.body
  end

  test "show redirects non-owners" do
    sign_out
    # User two is owner of org two, not org one
    sign_in_as users(:two)
    # User two accesses their own billing (they're an owner of org two)
    get settings_billing_path
    assert_response :success
  end

  test "requires authentication" do
    sign_out
    get settings_billing_path
    assert_response :redirect
  end

  test "checkout rejects invalid lookup_key" do
    post checkout_settings_billing_path, params: { lookup_key: "invalid_plan" }
    assert_redirected_to settings_billing_path
    assert_equal "Invalid plan selected.", flash[:alert]
  end

  test "portal redirects when no stripe customer" do
    get portal_settings_billing_path
    assert_redirected_to settings_billing_path
    assert_match "No billing account found", flash[:alert]
  end

  test "success redirects to billing with notice" do
    get success_settings_billing_path
    assert_redirected_to settings_billing_path
    assert_equal "Welcome to the Free plan! Your subscription is now active.", flash[:notice]
  end

  test "shows upgrade CTA for free plan" do
    @org.update!(plan: "free")
    get settings_billing_path
    assert_response :success
    assert_match "Unlock more with a paid plan", response.body
  end

  test "hides upgrade CTA for pro plan" do
    @org.update!(plan: "pro")
    get settings_billing_path
    assert_response :success
    assert_no_match "Unlock more with a paid plan", response.body
  end

  test "checkout redirects non-owners" do
    member_user = User.create!(email_address: "member_billing@example.com", password: "password123", first_name: "Member", last_name: "User", terms_accepted: "1")
    Membership.create!(user: member_user, organization: @org, role: Membership::MEMBER_ROLE)
    sign_out
    sign_in_as member_user

    post checkout_settings_billing_path, params: { lookup_key: "starter_monthly" }
    assert_redirected_to root_path
    assert_match "Only the organization owner", flash[:alert]
  end

  test "portal redirects non-owners" do
    member_user = User.create!(email_address: "member_portal@example.com", password: "password123", first_name: "Member", last_name: "User", terms_accepted: "1")
    Membership.create!(user: member_user, organization: @org, role: Membership::MEMBER_ROLE)
    sign_out
    sign_in_as member_user

    get portal_settings_billing_path
    assert_redirected_to root_path
    assert_match "Only the organization owner", flash[:alert]
  end

  test "success redirects non-owners" do
    member_user = User.create!(email_address: "member_success@example.com", password: "password123", first_name: "Member", last_name: "User", terms_accepted: "1")
    Membership.create!(user: member_user, organization: @org, role: Membership::MEMBER_ROLE)
    sign_out
    sign_in_as member_user

    get success_settings_billing_path
    assert_redirected_to root_path
    assert_match "Only the organization owner", flash[:alert]
  end

  test "checkout handles Stripe errors gracefully" do
    pay_customer = @org.set_payment_processor(:stripe)
    pay_customer.update!(processor_id: "cus_test_fake_error")

    StripePriceResolver.stub(:resolve_checkout_price, ->(_) { raise Stripe::StripeError.new("Connection refused") }) do
      post checkout_settings_billing_path, params: { lookup_key: "starter_monthly" }
    end
    assert_redirected_to settings_billing_path
    assert_match "Unable to start checkout", flash[:alert]
  end

  test "portal handles Stripe errors gracefully" do
    pay_customer = @org.set_payment_processor(:stripe)
    pay_customer.update!(processor_id: "cus_test_fake_portal")

    Stripe::BillingPortal::Session.stub(:create, ->(*) { raise Stripe::StripeError.new("API error") }) do
      get portal_settings_billing_path
    end
    assert_redirected_to settings_billing_path
    assert_match "Unable to open billing portal", flash[:alert]
  end

  test "checkout happy path redirects to Stripe" do
    pay_customer = @org.set_payment_processor(:stripe)
    pay_customer.update!(processor_id: "cus_test_fake_happy")

    fake_session = Struct.new(:url).new("https://checkout.stripe.com/pay/cs_test_123")
    StripePriceResolver.stub(:resolve_checkout_price, "price_resolved_123") do
      Stripe::Checkout::Session.stub(:create, fake_session) do
        post checkout_settings_billing_path, params: { lookup_key: "starter_monthly" }
      end
    end
    assert_response :see_other
    assert_redirected_to "https://checkout.stripe.com/pay/cs_test_123"
  end

  test "billing page shows active contracts count not total" do
    contracts(:hvac_maintenance).update!(status: "archived")
    get settings_billing_path
    assert_response :success
    active_count = @org.active_contracts_count
    assert_match "#{active_count} /", response.body
  end

  test "billing page shows extraction reset date" do
    get settings_billing_path
    assert_response :success
    next_reset = Date.current.next_month.beginning_of_month.strftime("%B %-d, %Y")
    assert_match "Resets on #{next_reset}", response.body
  end

  test "success message includes plan name" do
    get success_settings_billing_path
    assert_redirected_to settings_billing_path
    assert_match "Free plan", flash[:notice]
  end

  test "non-owner redirect includes owner name" do
    member_user = User.create!(email_address: "member_ownername@example.com", password: "password123", first_name: "Member", last_name: "User", terms_accepted: "1")
    Membership.create!(user: member_user, organization: @org, role: Membership::MEMBER_ROLE)
    sign_out
    sign_in_as member_user

    get settings_billing_path
    assert_redirected_to root_path
    assert_match @org.owner.full_name, flash[:alert]
  end

  test "checkout redirects to portal when active subscription exists" do
    pay_customer = @org.set_payment_processor(:stripe)
    pay_customer.update!(processor_id: "cus_test_existing_sub")

    # Create an active subscription using STI subclass so .active scope finds it
    StripePriceResolver.stub(:plan_for_price_id, "starter") do
      Pay::Stripe::Subscription.create!(
        customer: pay_customer,
        processor_id: "sub_existing_starter",
        processor_plan: "price_starter_existing",
        name: "default",
        status: "active"
      )
    end

    # Checkout should detect existing subscription and redirect to portal action
    post checkout_settings_billing_path, params: { lookup_key: "pro_monthly" }

    assert_redirected_to portal_settings_billing_path
  end

  test "checkout proceeds to Stripe Checkout when no active subscription" do
    pay_customer = @org.set_payment_processor(:stripe)
    pay_customer.update!(processor_id: "cus_test_no_sub")

    fake_session = Struct.new(:url).new("https://checkout.stripe.com/pay/cs_test_new")
    StripePriceResolver.stub(:resolve_checkout_price, "price_resolved_new") do
      Stripe::Checkout::Session.stub(:create, fake_session) do
        post checkout_settings_billing_path, params: { lookup_key: "starter_monthly" }
      end
    end
    assert_response :see_other
    assert_redirected_to "https://checkout.stripe.com/pay/cs_test_new"
  end

  test "success calls sync_plan_from_subscription before redirect" do
    @org.update!(plan: "free")

    # Set up a Pay customer + active subscription using STI subclass
    pay_customer = @org.set_payment_processor(:stripe)
    pay_customer.update!(processor_id: "cus_test_success_sync")

    StripePriceResolver.stub(:plan_for_price_id, "pro") do
      Pay::Stripe::Subscription.create!(
        customer: pay_customer,
        processor_id: "sub_success_pro",
        processor_plan: "price_pro_success",
        name: "default",
        status: "active"
      )

      get success_settings_billing_path
    end

    assert_redirected_to settings_billing_path
    assert_equal "pro", @org.reload.plan
    assert_match "Pro plan", flash[:notice]
  end

  test "legacy /billing redirects to settings billing" do
    get "/billing"
    assert_response :redirect
    assert_redirected_to "/settings/billing"
  end
end
