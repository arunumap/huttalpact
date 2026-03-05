require "test_helper"

class Settings::BillingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @org = organizations(:one)

    @default_plan_slug = PlanCatalogService.default_plan_slug
    @default_tier = PlanCatalogService.tier_for(@default_plan_slug)
    @paid_tiers = PlanCatalogService.active_tiers_for_billing.select(&:paid?).sort_by(&:rank)
    @base_paid_tier = @paid_tiers.first
    @top_paid_tier = @paid_tiers.last

    raise "Expected at least one paid tier for billing tests" unless @base_paid_tier

    @checkout_lookup_key = @base_paid_tier.monthly_lookup_key.presence || @base_paid_tier.annual_lookup_key
    @upgrade_lookup_key = @top_paid_tier.monthly_lookup_key.presence || @top_paid_tier.annual_lookup_key
    @downgrade_lookup_key = @base_paid_tier.monthly_lookup_key.presence || @base_paid_tier.annual_lookup_key

    raise "Expected checkout lookup key for billing tests" if @checkout_lookup_key.blank?
    raise "Expected upgrade lookup key for billing tests" if @upgrade_lookup_key.blank?

    sign_in_as @user
  end

  test "show renders billing page for owner" do
    get settings_billing_path
    assert_response :success
    assert_select "h2", text: "Choose Your Plan"
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
    assert_equal "Welcome to the #{@default_tier.name} plan! Your subscription is now active.", flash[:notice]
  end

  test "shows upgrade CTA for free plan" do
    @org.update!(plan: @default_plan_slug)
    get settings_billing_path
    assert_response :success
    assert_match "Get Started", response.body
  end

  test "hides upgrade CTA for pro plan" do
    @org.update!(plan: @top_paid_tier.slug)
    get settings_billing_path
    assert_response :success
    assert_match "Current Plan", response.body
  end

  test "checkout redirects non-owners" do
    member_user = User.create!(email_address: "member_billing@example.com", password: "password123", first_name: "Member", last_name: "User", terms_accepted: "1")
    Membership.create!(user: member_user, organization: @org, role: Membership::MEMBER_ROLE)
    sign_out
    sign_in_as member_user

    post checkout_settings_billing_path, params: { lookup_key: @checkout_lookup_key }
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
      post checkout_settings_billing_path, params: { lookup_key: @checkout_lookup_key }
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
        post checkout_settings_billing_path, params: { lookup_key: @checkout_lookup_key }
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
    next_reset = @org.extraction_period_end.strftime("%B %-d, %Y")
    assert_match "Resets on #{next_reset}", response.body
  end

  test "billing page shows overage usage and estimated charge" do
    @org.update!(
      plan: "starter",
      ai_extractions_count: 51,
      ai_extractions_overage_count: 1,
      ai_extractions_reset_at: Time.current
    )
    plan_tiers(:starter).update!(extraction_overage_cents: 125)

    get settings_billing_path
    assert_response :success
    assert_match "Overage usage this billing period: 1", response.body
    assert_match "$1.25", response.body
  end

  test "show displays extraction billing snapshot" do
    get settings_billing_path
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

  test "show extraction snapshot estimated bill includes base plan and accrued overage charges" do
    plan_tiers(:starter).update!(extraction_overage_cents: 50)
    @org.update!(plan: "starter", ai_extractions_count: 52, ai_extractions_overage_count: 2)
    create_active_subscription_for(@org, current_period_start: 10.days.ago, current_period_end: 20.days.from_now)

    get settings_billing_path
    assert_response :success

    assert_select "#extraction-billing-snapshot" do
      assert_select "dd", text: "$0.50"
      assert_select "dd", text: "$50.00"
    end
  end

  test "show extraction snapshot shows 80 percent warning" do
    @org.update!(plan: "starter", ai_extractions_count: 40, ai_extractions_overage_count: 0)

    get settings_billing_path
    assert_response :success
    assert_includes response.body, "You've used 80% of your AI extractions for this billing period."
  end

  test "show extraction snapshot shows upgrade nudge when higher tier lowers overage cost" do
    plan_tiers(:starter).update!(extraction_overage_cents: 50)
    plan_tiers(:pro).update!(extraction_limit: 500, extraction_overage_cents: 40)
    @org.update!(plan: "starter", ai_extractions_count: 40, ai_extractions_overage_count: 0)

    get settings_billing_path
    assert_response :success
    assert_includes response.body, "Upgrade to Pro and lower extraction overage cost by 20%."
  end

  test "show extraction snapshot hides upgrade nudge for unlimited higher tier even if overage is misconfigured" do
    plan_tiers(:starter).update!(extraction_overage_cents: 50)
    plan_tiers(:pro).update!(extraction_limit: nil, extraction_overage_cents: 40)
    @org.update!(plan: "starter", ai_extractions_count: 40, ai_extractions_overage_count: 0)

    get settings_billing_path
    assert_response :success
    assert_not_includes response.body, "Upgrade to Pro and lower extraction overage cost by"
  end

  test "success message includes plan name" do
    get success_settings_billing_path
    assert_redirected_to settings_billing_path
    assert_match "#{@default_tier.name} plan", flash[:notice]
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

  test "checkout redirects when active subscription exists" do
    pay_customer = @org.set_payment_processor(:stripe)
    pay_customer.update!(processor_id: "cus_test_existing_sub")

    # Create an active subscription using STI subclass so .active scope finds it
    StripePriceResolver.stub(:plan_for_price_id, @base_paid_tier.slug) do
      Pay::Stripe::Subscription.create!(
        customer: pay_customer,
        processor_id: "sub_existing_starter",
        processor_plan: "price_starter_existing",
        name: "default",
        status: "active"
      )
    end

    # Checkout should detect existing subscription and redirect back with error
    post checkout_settings_billing_path, params: { lookup_key: @upgrade_lookup_key }

    assert_redirected_to settings_billing_path
    assert_match "already have an active subscription", flash[:alert]
  end

  test "checkout proceeds to Stripe Checkout when no active subscription" do
    pay_customer = @org.set_payment_processor(:stripe)
    pay_customer.update!(processor_id: "cus_test_no_sub")

    fake_session = Struct.new(:url).new("https://checkout.stripe.com/pay/cs_test_new")
    StripePriceResolver.stub(:resolve_checkout_price, "price_resolved_new") do
      Stripe::Checkout::Session.stub(:create, fake_session) do
        post checkout_settings_billing_path, params: { lookup_key: @checkout_lookup_key }
      end
    end
    assert_response :see_other
    assert_redirected_to "https://checkout.stripe.com/pay/cs_test_new"
  end

  test "success calls sync_plan_from_subscription before redirect" do
    @org.update!(plan: @default_plan_slug)

    # Set up a Pay customer + active subscription using STI subclass
    pay_customer = @org.set_payment_processor(:stripe)
    pay_customer.update!(processor_id: "cus_test_success_sync")

    StripePriceResolver.stub(:plan_for_price_id, @top_paid_tier.slug) do
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
    assert_equal @top_paid_tier.slug, @org.reload.plan
    assert_match "#{@top_paid_tier.name} plan", flash[:notice]
  end

  test "legacy /billing redirects to settings billing" do
    get "/billing"
    assert_response :redirect
    assert_redirected_to "/settings/billing"
  end

  # --- upgrade action ---

  test "upgrade rejects invalid lookup_key" do
    post upgrade_settings_billing_path, params: { lookup_key: "bad_key" }
    assert_redirected_to settings_billing_path
    assert_equal "Invalid plan selected.", flash[:alert]
  end

  test "upgrade succeeds for valid upgrade" do
    @org.update!(plan: @base_paid_tier.slug)
    customer = @org.set_payment_processor(:stripe)
    customer.update!(processor_id: "cus_ctrl_upgrade")

    Pay::Stripe::Subscription.create!(
      customer: customer,
      processor_id: "sub_ctrl_upgrade",
      processor_plan: "price_starter_ctrl",
      name: "default",
      status: "active"
    )

    fake_service = build_fake_service(upgrade!: SubscriptionManagerService::Result.new(success: true))

    SubscriptionManagerService.stub(:new, ->(_org) { fake_service }) do
      post upgrade_settings_billing_path, params: { lookup_key: @upgrade_lookup_key }
    end
    assert_redirected_to settings_billing_path
    assert_match "upgraded to the #{@top_paid_tier.name} plan", flash[:notice]
  end

  test "upgrade shows error on failure" do
    fake_service = build_fake_service(upgrade!: SubscriptionManagerService::Result.new(success: false, error: "Not an upgrade"))

    SubscriptionManagerService.stub(:new, ->(_org) { fake_service }) do
      post upgrade_settings_billing_path, params: { lookup_key: @upgrade_lookup_key }
    end
    assert_redirected_to settings_billing_path
    assert_match "Not an upgrade", flash[:alert]
  end

  test "upgrade requires owner" do
    member_user = User.create!(email_address: "member_upgrade@example.com", password: "password123", first_name: "Member", last_name: "User", terms_accepted: "1")
    Membership.create!(user: member_user, organization: @org, role: Membership::MEMBER_ROLE)
    sign_out
    sign_in_as member_user

    post upgrade_settings_billing_path, params: { lookup_key: @upgrade_lookup_key }
    assert_redirected_to root_path
    assert_match "Only the organization owner", flash[:alert]
  end

  # --- downgrade action ---

  test "downgrade rejects invalid lookup_key" do
    post downgrade_settings_billing_path, params: { lookup_key: "bad_key" }
    assert_redirected_to settings_billing_path
    assert_equal "Invalid plan selected.", flash[:alert]
  end

  test "downgrade succeeds and shows effective date" do
    @org.update!(plan: @top_paid_tier.slug)
    effective_date = 30.days.from_now

    fake_service = build_fake_service(schedule_downgrade!: SubscriptionManagerService::Result.new(success: true))

    SubscriptionManagerService.stub(:new, ->(_org) { fake_service }) do
      @org.update!(pending_plan: @base_paid_tier.slug, pending_plan_effective_at: effective_date)
      post downgrade_settings_billing_path, params: { lookup_key: @downgrade_lookup_key }
    end
    assert_redirected_to settings_billing_path
    assert_match @base_paid_tier.name, flash[:notice]
  end

  test "downgrade shows error on failure" do
    fake_service = build_fake_service(schedule_downgrade!: SubscriptionManagerService::Result.new(success: false, error: "Too many contracts"))

    SubscriptionManagerService.stub(:new, ->(_org) { fake_service }) do
      post downgrade_settings_billing_path, params: { lookup_key: @downgrade_lookup_key }
    end
    assert_redirected_to settings_billing_path
    assert_match "Too many contracts", flash[:alert]
  end

  # --- cancel_downgrade action ---

  test "cancel_downgrade succeeds" do
    @org.update!(plan: @top_paid_tier.slug, pending_plan: @base_paid_tier.slug, pending_downgrade_schedule_id: "sub_sched_x")

    fake_service = build_fake_service(cancel_scheduled_downgrade!: SubscriptionManagerService::Result.new(success: true))

    SubscriptionManagerService.stub(:new, ->(_org) { fake_service }) do
      post cancel_downgrade_settings_billing_path
    end
    assert_redirected_to settings_billing_path
    assert_match "downgrade has been canceled", flash[:notice]
  end

  test "cancel_downgrade shows error on failure" do
    fake_service = build_fake_service(cancel_scheduled_downgrade!: SubscriptionManagerService::Result.new(success: false, error: "No pending downgrade"))

    SubscriptionManagerService.stub(:new, ->(_org) { fake_service }) do
      post cancel_downgrade_settings_billing_path
    end
    assert_redirected_to settings_billing_path
    assert_match "No pending downgrade", flash[:alert]
  end

  # --- cancel_subscription action ---

  test "cancel_subscription succeeds" do
    @org.update!(plan: @base_paid_tier.slug)
    customer = @org.set_payment_processor(:stripe)
    customer.update!(processor_id: "cus_ctrl_cancel")

    Pay::Stripe::Subscription.create!(
      customer: customer,
      processor_id: "sub_ctrl_cancel",
      processor_plan: "price_starter_cancel",
      name: "default",
      status: "active",
      ends_at: 30.days.from_now
    )

    fake_service = build_fake_service(cancel_subscription!: SubscriptionManagerService::Result.new(success: true))

    SubscriptionManagerService.stub(:new, ->(_org) { fake_service }) do
      post cancel_subscription_settings_billing_path
    end
    assert_redirected_to settings_billing_path
    assert_match "subscription will remain active", flash[:notice]
  end

  test "cancel_subscription shows error on failure" do
    fake_service = build_fake_service(cancel_subscription!: SubscriptionManagerService::Result.new(success: false, error: "No active subscription found"))

    SubscriptionManagerService.stub(:new, ->(_org) { fake_service }) do
      post cancel_subscription_settings_billing_path
    end
    assert_redirected_to settings_billing_path
    assert_match "No active subscription found", flash[:alert]
  end

  # --- resume_subscription action ---

  test "resume_subscription succeeds" do
    @org.update!(plan: @base_paid_tier.slug)

    fake_service = build_fake_service(resume_subscription!: SubscriptionManagerService::Result.new(success: true))

    SubscriptionManagerService.stub(:new, ->(_org) { fake_service }) do
      post resume_subscription_settings_billing_path
    end
    assert_redirected_to settings_billing_path
    assert_match "subscription has been resumed", flash[:notice]
  end

  test "resume_subscription shows error on failure" do
    fake_service = build_fake_service(resume_subscription!: SubscriptionManagerService::Result.new(success: false, error: "No active subscription"))

    SubscriptionManagerService.stub(:new, ->(_org) { fake_service }) do
      post resume_subscription_settings_billing_path
    end
    assert_redirected_to settings_billing_path
    assert_match "No active subscription", flash[:alert]
  end

  # --- destroy_account action ---

  test "destroy_account succeeds with correct password" do
    fake_service = build_fake_service(destroy_account!: SubscriptionManagerService::Result.new(success: true))

    SubscriptionManagerService.stub(:new, ->(_org) { fake_service }) do
      delete destroy_account_settings_billing_path, params: { password: "password" }
    end
    assert_redirected_to root_path
    assert_match "permanently deleted", flash[:notice]
  end

  test "destroy_account fails with wrong password" do
    fake_service = build_fake_service(destroy_account!: SubscriptionManagerService::Result.new(success: false, error: "Incorrect password."))

    SubscriptionManagerService.stub(:new, ->(_org) { fake_service }) do
      delete destroy_account_settings_billing_path, params: { password: "wrongpass" }
    end
    assert_redirected_to settings_billing_path
    assert_match "Incorrect password", flash[:alert]
  end

  test "destroy_account requires owner" do
    member_user = User.create!(email_address: "member_destroy@example.com", password: "password123", first_name: "Member", last_name: "User", terms_accepted: "1")
    Membership.create!(user: member_user, organization: @org, role: Membership::MEMBER_ROLE)
    sign_out
    sign_in_as member_user

    delete destroy_account_settings_billing_path, params: { password: "password123" }
    assert_redirected_to root_path
    assert_match "Only the organization owner", flash[:alert]
  end

  # --- show action with pending states ---

  test "show displays pending downgrade banner" do
    @org.update!(plan: @top_paid_tier.slug, pending_plan: @base_paid_tier.slug, pending_plan_effective_at: 30.days.from_now, pending_downgrade_schedule_id: "sub_sched_show")
    get settings_billing_path
    assert_response :success
    assert_match "pending downgrade", response.body.downcase
  end

  test "show displays pending cancellation banner" do
    @org.update!(plan: @base_paid_tier.slug)
    customer = @org.set_payment_processor(:stripe)
    customer.update!(processor_id: "cus_show_cancel")

    Pay::Stripe::Subscription.create!(
      customer: customer,
      processor_id: "sub_show_cancel",
      processor_plan: "price_starter_show",
      name: "default",
      status: "active",
      ends_at: 30.days.from_now
    )

    get settings_billing_path
    assert_response :success
    assert_match "cancel", response.body.downcase
  end

  private

  def create_active_subscription_for(org, current_period_start:, current_period_end:)
    customer = org.set_payment_processor(:stripe)
    customer.update!(processor_id: "cus_billing_snapshot_#{SecureRandom.hex(4)}")

    Pay::Stripe::Subscription.create!(
      customer: customer,
      processor_id: "sub_billing_snapshot_#{SecureRandom.hex(4)}",
      processor_plan: "price_billing_snapshot_monthly",
      name: "default",
      status: "active",
      current_period_start: current_period_start,
      current_period_end: current_period_end
    )
  end

  # Build a fake service object that responds to stubbed methods
  def build_fake_service(**method_results)
    fake = Object.new
    method_results.each do |method_name, result|
      fake.define_singleton_method(method_name) { |*_args| result }
    end
    fake
  end
end
