class Settings::BillingController < ApplicationController
  include PlanEnforcement

  before_action :require_owner

  def show
    @organization = current_organization
    @subscription = @organization.active_subscription
    @pending_downgrade = @organization.pending_downgrade?
    @pending_cancellation = @organization.pending_cancellation?
    @plan_tiers = PlanCatalogService.active_tiers_for_billing
    set_extraction_dashboard_summary

    # Precompute downgrade eligibility for lower plans
    @downgrade_eligibility = {}
    PlanCatalogService.plan_hierarchy.each_key do |plan_name|
      if @organization.downgrade_from_current?(plan_name)
        @downgrade_eligibility[plan_name] = @organization.downgrade_eligibility(plan_name)
      end
    end
  end

  def checkout
    lookup_key = params[:lookup_key]

    unless PlanCatalogService.valid_lookup_key?(lookup_key)
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

    track_analytics_event("begin_checkout", plan: PlanCatalogService.plan_for_lookup_key(lookup_key))
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

    unless PlanCatalogService.valid_lookup_key?(lookup_key)
      redirect_to settings_billing_path, alert: "Invalid plan selected."
      return
    end

    service = SubscriptionManagerService.new(current_organization)
    result = service.upgrade!(lookup_key)

    if result.success?
      target_plan = PlanCatalogService.plan_for_lookup_key(lookup_key)
      track_analytics_event("plan_upgraded", plan: target_plan)
      redirect_to settings_billing_path, notice: "You've been upgraded to the #{target_plan.titleize} plan! Changes are effective immediately."
    else
      redirect_to settings_billing_path, alert: result.error
    end
  end

  def downgrade
    lookup_key = params[:lookup_key]

    unless PlanCatalogService.valid_lookup_key?(lookup_key)
      redirect_to settings_billing_path, alert: "Invalid plan selected."
      return
    end

    service = SubscriptionManagerService.new(current_organization)
    result = service.schedule_downgrade!(lookup_key)

    if result.success?
      target_plan = PlanCatalogService.plan_for_lookup_key(lookup_key)
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

    current_tier = PlanCatalogService.tier_for(current_organization.plan)
    monthly_value = current_tier ? (current_tier.monthly_price_cents.to_i / 100) : 0
    track_analytics_event("purchase", plan: current_organization.plan, value: monthly_value, currency: "USD")

    redirect_to settings_billing_path, notice: "Welcome to the #{current_organization.plan_display_name} plan! Your subscription is now active."
  end

  private

  def set_extraction_dashboard_summary
    org = current_organization
    return unless org

    limit = org.plan_extraction_limit
    @dashboard_extraction_limit_display = limit == Float::INFINITY ? "∞" : limit
    @dashboard_extraction_usage_percent = if limit == Float::INFINITY || limit.to_i <= 0
      0
    else
      ((org.ai_extractions_count.to_f / limit) * 100).round
    end

    @dashboard_overage_rate_cents = org.plan_extraction_overage_cents
    @dashboard_estimated_bill_cents = estimated_dashboard_bill_cents_for(org)
    @dashboard_upgrade_overage_nudge = dashboard_upgrade_overage_nudge_for(org)
  end

  def estimated_dashboard_bill_cents_for(org)
    estimated_base_subscription_cents_for(org) + org.estimated_extraction_overage_cents
  end

  def estimated_base_subscription_cents_for(org)
    tier = PlanCatalogService.tier_for(org.plan)
    return 0 unless tier

    inferred_subscription_interval(org.active_subscription) == :annual ? tier.annual_price_cents.to_i : tier.monthly_price_cents.to_i
  end

  def inferred_subscription_interval(subscription)
    return :monthly unless subscription&.current_period_start && subscription&.current_period_end

    period_days = (subscription.current_period_end.to_date - subscription.current_period_start.to_date).to_i
    period_days > 45 ? :annual : :monthly
  end

  def dashboard_upgrade_overage_nudge_for(org)
    limit = org.plan_extraction_limit
    return nil if limit == Float::INFINITY
    return nil unless @dashboard_extraction_usage_percent >= 80

    current_tier = PlanCatalogService.tier_for(org.plan)
    return nil unless current_tier

    current_rate_cents = current_tier.extraction_overage_cents.to_i
    return nil unless current_rate_cents.positive?

    cheaper_tier, cheaper_rate_cents = PlanCatalogService.active_tiers_for_billing
      .select { |tier| tier.rank.to_i > current_tier.rank.to_i }
      .map { |tier| [ tier, candidate_overage_rate_cents(tier) ] }
      .select { |_, rate| rate.present? && rate < current_rate_cents }
      .min_by { |_, rate| rate }

    return nil unless cheaper_tier && cheaper_rate_cents

    savings_percent = ((current_rate_cents - cheaper_rate_cents) * 100.0 / current_rate_cents).round
    return nil if savings_percent <= 0

    { tier_name: cheaper_tier.name, savings_percent: savings_percent }
  end

  def candidate_overage_rate_cents(tier)
    rate = tier.extraction_overage_cents.to_i
    return nil unless rate.positive?
    return nil if tier.extraction_limit.nil?

    rate
  end

  def require_owner
    membership = current_organization&.memberships&.find_by(user: Current.user)
    return if membership&.role == Membership::OWNER_ROLE

    owner = current_organization&.owner
    redirect_to root_path, alert: "Only the organization owner#{owner ? " (#{owner.full_name})" : ''} can manage billing."
  end
end
