class Admin::BillingController < Admin::BaseController
  def show
    @plan_distribution = Organization.group(:plan).count

    if defined?(Pay::Subscription)
      @active_subscriptions = Pay::Subscription.where(status: "active").includes(:customer).order(created_at: :desc)
      @recent_charges = Pay::Charge.includes(:customer).order(created_at: :desc).limit(50)
      @recent_webhooks = Pay::Webhook.order(created_at: :desc).limit(50)
      @revenue_last_30_days_cents = Pay::Charge.where(created_at: 30.days.ago..).sum(:amount)
    else
      @active_subscriptions = []
      @recent_charges = []
      @recent_webhooks = []
      @revenue_last_30_days_cents = 0
    end

    # Stripe management data
    @stripe_status = StripeAdminService.verify_products_and_prices
    @portal_configuration_id = Rails.application.credentials.dig(:stripe, :portal_configuration_id)
    @organizations_with_subscriptions = load_organizations_with_subscriptions
  end

  def setup_stripe
    result = StripeAdminService.setup_products_and_prices!

    if result[:success]
      created = result[:created]
      skipped = result[:skipped]
      flash[:notice] = "Stripe setup complete. Created: #{created.join(', ').presence || 'none'}. Skipped: #{skipped.join(', ').presence || 'none'}."
    else
      flash[:alert] = "Stripe setup failed: #{result[:message]}"
    end

    redirect_to admin_billing_path
  end

  def configure_portal
    result = StripeAdminService.configure_billing_portal!

    if result[:success]
      flash[:notice] = "Portal configuration created: #{result[:configuration_id]}. Add this to your Rails credentials under stripe.portal_configuration_id."
    else
      flash[:alert] = "Portal configuration failed: #{result[:message]}"
    end

    redirect_to admin_billing_path
  end

  def sync_all_organizations
    result = StripeAdminService.sync_all_organizations!

    if result[:success]
      changed_count = result[:details]&.count { |d| d[:changed] } || 0
      flash[:notice] = "Synced #{result[:synced]} organizations. #{changed_count} plan(s) updated. #{result[:failed]} failed."
    else
      flash[:alert] = "Sync failed: #{result[:message]}"
    end

    redirect_to admin_billing_path
  end

  def sync_organization
    org = Organization.find(params[:organization_id])
    result = StripeAdminService.sync_organization!(org)

    if result[:success]
      if result[:changed]
        flash[:notice] = "#{org.name}: plan updated from #{result[:old_plan]} to #{result[:new_plan]}."
      else
        flash[:notice] = "#{org.name}: plan already in sync (#{result[:new_plan]})."
      end
    else
      flash[:alert] = "Sync failed for #{org.name}: #{result[:message]}"
    end

    redirect_to admin_billing_path
  rescue ActiveRecord::RecordNotFound
    flash[:alert] = "Organization not found."
    redirect_to admin_billing_path
  end

  private

  def load_organizations_with_subscriptions
    return [] unless defined?(Pay::Subscription)

    Organization.joins(pay_customers: :subscriptions)
                .where(pay_subscriptions: { status: "active" })
                .distinct
                .includes(:pay_customers)
  rescue => e
    Rails.logger.warn("Failed to load organizations with subscriptions: #{e.message}")
    []
  end
end
