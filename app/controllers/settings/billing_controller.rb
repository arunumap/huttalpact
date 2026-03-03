class Settings::BillingController < ApplicationController
  include PlanEnforcement

  before_action :require_owner

  def show
    @organization = current_organization
    @subscription = @organization.active_subscription
    @pending_downgrade = @organization.pending_downgrade?
    @pending_cancellation = @organization.pending_cancellation?

    # Precompute downgrade eligibility for lower plans
    @downgrade_eligibility = {}
    PlanLimits::PLAN_HIERARCHY.each_key do |plan_name|
      if @organization.downgrade_from_current?(plan_name)
        @downgrade_eligibility[plan_name] = @organization.downgrade_eligibility(plan_name)
      end
    end
  end

  def checkout
    lookup_key = params[:lookup_key]

    unless PlanLimits::LOOKUP_KEYS.key?(lookup_key)
      redirect_to settings_billing_path, alert: "Invalid plan selected."
      return
    end

    # Checkout is only for free-plan users (no existing subscription)
    if current_organization.active_subscription
      redirect_to settings_billing_path, alert: "You already have an active subscription. Use the upgrade option instead."
      return
    end

    price_id = StripePriceResolver.resolve_checkout_price(lookup_key)
    customer = current_organization.set_payment_processor(:stripe)
    session = customer.checkout(
      mode: "subscription",
      line_items: [ { price: price_id, quantity: 1 } ],
      success_url: success_settings_billing_url + "?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: settings_billing_url
    )

    track_analytics_event("begin_checkout", plan: PlanLimits::LOOKUP_KEYS[lookup_key])
    redirect_to session.url, allow_other_host: true, status: :see_other
  rescue StripePriceResolver::PriceNotFound => e
    Rails.logger.error("Stripe price not found for org #{current_organization.id}: #{e.message}")
    redirect_to settings_billing_path, alert: "Plan not available. Please try again or contact support."
  rescue Pay::Error, Stripe::StripeError => e
    Rails.logger.error("Stripe checkout error for org #{current_organization.id}: #{e.message}")
    redirect_to settings_billing_path, alert: "Unable to start checkout. Please try again."
  end

  def upgrade
    lookup_key = params[:lookup_key]

    unless PlanLimits::LOOKUP_KEYS.key?(lookup_key)
      redirect_to settings_billing_path, alert: "Invalid plan selected."
      return
    end

    service = SubscriptionManagerService.new(current_organization)
    result = service.upgrade!(lookup_key)

    if result.success?
      target_plan = PlanLimits::LOOKUP_KEYS[lookup_key]
      track_analytics_event("plan_upgraded", plan: target_plan)
      redirect_to settings_billing_path, notice: "You've been upgraded to the #{target_plan.titleize} plan! Changes are effective immediately."
    else
      redirect_to settings_billing_path, alert: result.error
    end
  end

  def downgrade
    lookup_key = params[:lookup_key]

    unless PlanLimits::LOOKUP_KEYS.key?(lookup_key)
      redirect_to settings_billing_path, alert: "Invalid plan selected."
      return
    end

    service = SubscriptionManagerService.new(current_organization)
    result = service.schedule_downgrade!(lookup_key)

    if result.success?
      target_plan = PlanLimits::LOOKUP_KEYS[lookup_key]
      effective_date = current_organization.pending_plan_effective_at&.strftime("%B %-d, %Y")
      redirect_to settings_billing_path, notice: "Your plan will change to #{target_plan.titleize} on #{effective_date}."
    else
      redirect_to settings_billing_path, alert: "Unable to downgrade: #{result.error}"
    end
  end

  def cancel_downgrade
    service = SubscriptionManagerService.new(current_organization)
    result = service.cancel_scheduled_downgrade!

    if result.success?
      redirect_to settings_billing_path, notice: "Your downgrade has been canceled. You'll stay on the #{current_organization.plan.titleize} plan."
    else
      redirect_to settings_billing_path, alert: result.error
    end
  end

  def cancel_subscription
    service = SubscriptionManagerService.new(current_organization)
    result = service.cancel_subscription!

    if result.success?
      subscription = current_organization.active_subscription
      end_date = subscription&.ends_at&.strftime("%B %-d, %Y") || subscription&.current_period_end&.strftime("%B %-d, %Y")
      redirect_to settings_billing_path, notice: "Your subscription will remain active until #{end_date}. You'll then be moved to the Free plan."
    else
      redirect_to settings_billing_path, alert: result.error
    end
  end

  def resume_subscription
    service = SubscriptionManagerService.new(current_organization)
    result = service.resume_subscription!

    if result.success?
      redirect_to settings_billing_path, notice: "Your subscription has been resumed. You'll stay on the #{current_organization.plan.titleize} plan."
    else
      redirect_to settings_billing_path, alert: result.error
    end
  end

  def destroy_account
    service = SubscriptionManagerService.new(current_organization)
    result = service.destroy_account!(params[:password])

    if result.success?
      # Sign out and redirect
      Current.session&.destroy
      cookies.delete(:session_id)
      redirect_to root_path, notice: "Your account and all data have been permanently deleted."
    else
      redirect_to settings_billing_path, alert: result.error
    end
  end

  def portal
    customer = current_organization.pay_customers&.find_by(processor: :stripe)

    unless customer
      redirect_to settings_billing_path, alert: "No billing account found. Please subscribe to a plan first."
      return
    end

    portal_options = { return_url: settings_billing_url }

    # Restrict portal to payment methods and invoices if configured
    portal_config_id = Rails.application.credentials.dig(:stripe, :portal_configuration_id)
    portal_options[:configuration] = portal_config_id if portal_config_id.present?

    session = customer.billing_portal(**portal_options)
    redirect_to session.url, allow_other_host: true, status: :see_other
  rescue Pay::Error, Stripe::StripeError => e
    Rails.logger.error("Stripe portal error for org #{current_organization.id}: #{e.message}")
    redirect_to settings_billing_path, alert: "Unable to open billing portal. Please try again."
  end

  def success
    current_organization.sync_plan_from_subscription!
    current_organization.reload
    track_analytics_event("purchase", plan: current_organization.plan, value: current_organization.plan == "pro" ? 149 : 49, currency: "USD")
    redirect_to settings_billing_path, notice: "Welcome to the #{current_organization.plan_display_name} plan! Your subscription is now active."
  end

  private

  def require_owner
    membership = current_organization&.memberships&.find_by(user: Current.user)
    return if membership&.role == Membership::OWNER_ROLE

    owner = current_organization&.owner
    redirect_to root_path, alert: "Only the organization owner#{owner ? " (#{owner.full_name})" : ''} can manage billing."
  end
end
