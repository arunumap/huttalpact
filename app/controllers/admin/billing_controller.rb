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
  end
end
