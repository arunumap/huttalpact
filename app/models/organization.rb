class Organization < ApplicationRecord
  include PlanLimits

  pay_customer default_payment_processor: :stripe

  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :contracts, dependent: :destroy
  has_many :alerts, dependent: :destroy
  has_many :alert_preferences, dependent: :destroy
  has_many :invitations, dependent: :destroy
  has_many :ai_usage_logs, dependent: :destroy

  validates :name, presence: true, length: { maximum: 255 }
  validates :slug, presence: true, uniqueness: true, length: { maximum: 100 },
            format: { with: /\A[a-z0-9\-]+\z/, message: "only allows lowercase letters, numbers, and hyphens" }
  validate :plan_must_be_known
  validate :pending_plan_must_be_known

  before_validation :generate_slug, on: :create

  ONBOARDING_STEPS = %w[organization contract invite].freeze

  def owner
    memberships.find_by(role: Membership::OWNER_ROLE)&.user
  end

  def email
    owner&.email_address
  end

  def onboarding_complete?
    onboarding_completed_at.present?
  end

  def onboarding_step_name
    ONBOARDING_STEPS[onboarding_step.to_i] || ONBOARDING_STEPS.first
  end

  def onboarding_step_index
    onboarding_step.to_i
  end

  def advance_onboarding!(step_name)
    index = ONBOARDING_STEPS.index(step_name) || 0
    update!(onboarding_step: [ onboarding_step_index, index ].max)
  end

  def complete_onboarding!
    update!(
      onboarding_step: ONBOARDING_STEPS.length - 1,
      onboarding_completed_at: Time.current
    )
  end

  def active_subscription
    pay_customers&.first&.subscriptions&.active&.order(created_at: :desc)&.first
  end

  def clear_pending_downgrade!
    update!(
      pending_plan: nil,
      pending_plan_interval: nil,
      pending_plan_effective_at: nil,
      pending_downgrade_schedule_id: nil
    )
  end

  def sync_plan_from_subscription!
    subscription = active_subscription

    if subscription
      plan_name = StripePriceResolver.plan_for_price_id(subscription.processor_plan)

      if plan_name.nil?
        Rails.logger.warn("Unknown Stripe price ID '#{subscription.processor_plan}' for org #{id}. Plan not updated.")
        return
      end

      if plan_name != plan
        old_plan = plan
        update!(plan: plan_name)
        log_plan_change(old_plan, plan_name)
      end
    else
      default_plan_slug = PlanCatalogService.default_plan_slug

      unless plan == default_plan_slug
        old_plan = plan
        update!(plan: default_plan_slug)
        log_plan_change(old_plan, default_plan_slug)
      end
    end

    # Clear pending downgrade if the plan now matches what was scheduled
    clear_pending_downgrade! if pending_downgrade? && plan == pending_plan
  end

  private

  def log_plan_change(old_plan, new_plan)
    AuditLog.create(
      organization: self,
      action: "plan_changed",
      details: "Plan changed from #{old_plan.titleize} to #{new_plan.titleize}"
    )
  rescue => e
    Rails.logger.error("Failed to log plan change audit for org #{id}: #{e.message}")
  end

  def plan_must_be_known
    return if plan.blank?
    return if PlanCatalogService.valid_plan_slug?(plan)

    errors.add(:plan, "is not included in the list")
  end

  def pending_plan_must_be_known
    return if pending_plan.blank?
    return if PlanCatalogService.valid_plan_slug?(pending_plan)

    errors.add(:pending_plan, "is not included in the list")
  end

  MAX_SLUG_RETRIES = 5

  def generate_slug
    return if slug.present?
    base_slug = name.to_s.parameterize.truncate(80, omission: "")
    base_slug = "org" if base_slug.blank?
    self.slug = base_slug
    counter = 1
    while Organization.exists?(slug: self.slug)
      self.slug = "#{base_slug}-#{counter}"
      counter += 1
    end
  rescue ActiveRecord::RecordNotUnique
    counter ||= 1
    counter += 1
    retry if counter <= MAX_SLUG_RETRIES
    raise
  end
end
