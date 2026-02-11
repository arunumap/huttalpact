class BillingController < ApplicationController
  include PlanEnforcement

  before_action :require_owner

  def show
    @organization = current_organization
    @subscription = @organization.pay_customers&.first&.subscriptions&.active&.first
  end

  def checkout
    price_id = params[:price_id]

    unless PlanLimits::PRICE_TO_PLAN.key?(price_id)
      redirect_to billing_path, alert: "Invalid plan selected."
      return

    end

    customer = current_organization.set_payment_processor(:stripe)
    session = customer.checkout(
      mode: "subscription",
      line_items: [ { price: price_id, quantity: 1 } ],
      success_url: success_billing_url + "?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: billing_url
    )

    redirect_to session.url, allow_other_host: true, status: :see_other
  rescue Pay::Error, Stripe::StripeError => e
    Rails.logger.error("Stripe checkout error for org #{current_organization.id}: #{e.message}")
    redirect_to billing_path, alert: "Unable to start checkout. Please try again."
  end

  def portal
    customer = current_organization.pay_customers&.find_by(processor: :stripe)

    unless customer
      redirect_to billing_path, alert: "No billing account found. Please subscribe to a plan first."
      return
    end

    session = customer.billing_portal(return_url: billing_url)
    redirect_to session.url, allow_other_host: true, status: :see_other
  rescue Pay::Error, Stripe::StripeError => e
    Rails.logger.error("Stripe portal error for org #{current_organization.id}: #{e.message}")
    redirect_to billing_path, alert: "Unable to open billing portal. Please try again."
  end

  def success
    current_organization.reload
    redirect_to billing_path, notice: "Welcome to the #{current_organization.plan_display_name} plan! Your subscription is now active."
  end

  private

  def require_owner
    membership = current_organization&.memberships&.find_by(user: Current.user)
    return if membership&.role == Membership::OWNER_ROLE

    owner = current_organization&.owner
    redirect_to root_path, alert: "Only the organization owner#{owner ? " (#{owner.full_name})" : ''} can manage billing."
  end
end
