class SubscriptionManagerService
  Result = Struct.new(:success, :error, keyword_init: true) do
    def success?
      success
    end
  end

  LOOKUP_KEY_INTERVALS = {
    "starter_monthly" => "monthly",
    "starter_annual"  => "annual",
    "pro_monthly"     => "monthly",
    "pro_annual"      => "annual"
  }.freeze

  def initialize(organization)
    @organization = organization
  end

  # In-place plan upgrade for existing subscribers (Starter → Pro, or interval change)
  def upgrade!(lookup_key)
    target_plan = PlanLimits::LOOKUP_KEYS[lookup_key]
    return error_result("Invalid plan selected.") unless target_plan

    unless @organization.upgrade_from_current?(target_plan)
      return error_result("#{target_plan.titleize} is not an upgrade from your current #{@organization.plan.titleize} plan.")
    end

    subscription = @organization.active_subscription
    return error_result("No active subscription found. Please use checkout to subscribe.") unless subscription

    # If there's a pending downgrade, cancel the schedule first
    if @organization.pending_downgrade?
      cancel_stripe_schedule!(@organization.pending_downgrade_schedule_id)
      @organization.clear_pending_downgrade!
    end

    new_price_id = StripePriceResolver.resolve_checkout_price(lookup_key)
    subscription.swap(new_price_id)

    # Sync the plan immediately
    @organization.sync_plan_from_subscription!

    log_audit("Upgraded to #{target_plan.titleize} plan")
    success_result
  rescue StripePriceResolver::PriceNotFound => e
    error_result("Plan not available: #{e.message}")
  rescue Pay::Error, Stripe::StripeError => e
    Rails.logger.error("Upgrade error for org #{@organization.id}: #{e.message}")
    error_result("Unable to process upgrade. Please try again.")
  end

  # Schedule a downgrade at the end of the current billing period
  def schedule_downgrade!(lookup_key)
    target_plan = PlanLimits::LOOKUP_KEYS[lookup_key]
    target_interval = LOOKUP_KEY_INTERVALS[lookup_key]
    return error_result("Invalid plan selected.") unless target_plan

    unless @organization.downgrade_from_current?(target_plan)
      return error_result("#{target_plan.titleize} is not a downgrade from your current #{@organization.plan.titleize} plan.")
    end

    eligibility = @organization.downgrade_eligibility(target_plan)
    unless eligibility[:eligible]
      return error_result(eligibility[:blockers].join(" "))
    end

    subscription = @organization.active_subscription
    return error_result("No active subscription found.") unless subscription

    new_price_id = StripePriceResolver.resolve_checkout_price(lookup_key)

    # Create a Stripe Subscription Schedule to transition at period end
    stripe_sub = Stripe::Subscription.retrieve(subscription.processor_id)
    schedule = Stripe::SubscriptionSchedule.create({
      from_subscription: stripe_sub.id
    })

    # Update the schedule with phases: current phase + downgrade phase
    current_phase_end = stripe_sub.current_period_end
    Stripe::SubscriptionSchedule.update(schedule.id, {
      end_behavior: "release",
      phases: [
        {
          items: [ { price: stripe_sub.items.data.first.price.id, quantity: 1 } ],
          start_date: schedule.phases.first.start_date,
          end_date: current_phase_end
        },
        {
          items: [ { price: new_price_id, quantity: 1 } ],
          start_date: current_phase_end
        }
      ]
    })

    # Store pending downgrade state
    @organization.update!(
      pending_plan: target_plan,
      pending_plan_interval: target_interval,
      pending_plan_effective_at: Time.zone.at(current_phase_end),
      pending_downgrade_schedule_id: schedule.id
    )

    log_audit("Scheduled downgrade to #{target_plan.titleize} plan on #{Time.zone.at(current_phase_end).strftime('%B %-d, %Y')}")
    success_result
  rescue StripePriceResolver::PriceNotFound => e
    error_result("Plan not available: #{e.message}")
  rescue Pay::Error, Stripe::StripeError => e
    Rails.logger.error("Downgrade scheduling error for org #{@organization.id}: #{e.message}")
    error_result("Unable to schedule downgrade. Please try again.")
  end

  # Cancel a pending downgrade schedule
  def cancel_scheduled_downgrade!
    schedule_id = @organization.pending_downgrade_schedule_id
    return error_result("No pending downgrade to cancel.") unless schedule_id.present?

    cancel_stripe_schedule!(schedule_id)
    @organization.clear_pending_downgrade!

    log_audit("Canceled pending downgrade — staying on #{@organization.plan.titleize} plan")
    success_result
  rescue Pay::Error, Stripe::StripeError => e
    Rails.logger.error("Cancel downgrade error for org #{@organization.id}: #{e.message}")
    error_result("Unable to cancel downgrade. Please try again.")
  end

  # Cancel subscription at end of billing period
  def cancel_subscription!
    subscription = @organization.active_subscription
    return error_result("No active subscription found.") unless subscription

    subscription.cancel
    log_audit("Canceled subscription — will revert to Free plan at period end")
    success_result
  rescue Pay::Error, Stripe::StripeError => e
    Rails.logger.error("Cancel subscription error for org #{@organization.id}: #{e.message}")
    error_result("Unable to cancel subscription. Please try again.")
  end

  # Resume a canceled subscription before period end
  def resume_subscription!
    subscription = @organization.active_subscription
    return error_result("No active subscription found.") unless subscription

    subscription.resume
    log_audit("Resumed subscription — staying on #{@organization.plan.titleize} plan")
    success_result
  rescue Pay::Error, Stripe::StripeError => e
    Rails.logger.error("Resume subscription error for org #{@organization.id}: #{e.message}")
    error_result("Unable to resume subscription. Please try again.")
  end

  # Permanently delete account
  def destroy_account!(password)
    owner = @organization.owner
    return error_result("Organization owner not found.") unless owner
    return error_result("Incorrect password.") unless owner.authenticate(password)

    subscription = @organization.active_subscription
    subscription&.cancel_now!

    @organization.destroy!
    success_result
  rescue Pay::Error, Stripe::StripeError => e
    Rails.logger.error("Account deletion error for org #{@organization.id}: #{e.message}")
    error_result("Unable to delete account. Please try again.")
  end

  private

  def success_result
    Result.new(success: true)
  end

  def error_result(message)
    Result.new(success: false, error: message)
  end

  def cancel_stripe_schedule!(schedule_id)
    return unless schedule_id.present?

    Stripe::SubscriptionSchedule.release(schedule_id)
  end

  def log_audit(details)
    AuditLog.create(
      organization: @organization,
      action: "plan_changed",
      details: details
    )
  rescue => e
    Rails.logger.error("Failed to log audit for org #{@organization.id}: #{e.message}")
  end
end
