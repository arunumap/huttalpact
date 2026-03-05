class PlanTier < ApplicationRecord
  FREE_SLUG = "free".freeze

  scope :ordered, -> { order(:position, :rank, :created_at) }
  scope :active, -> { where(active: true) }
  scope :visible_on_pricing_page, -> { where(visible_on_pricing_page: true) }

  validates :slug, presence: true,
                   uniqueness: true,
                   length: { maximum: 80 },
                   format: { with: /\A[a-z0-9\-]+\z/, message: "only allows lowercase letters, numbers, and hyphens" }
  validates :name, presence: true, length: { maximum: 120 }
  validates :rank, presence: true, uniqueness: true
  validates :position, presence: true, numericality: { only_integer: true }
  validates :contract_limit, numericality: { greater_than: 0, only_integer: true }, allow_nil: true
  validates :extraction_limit, numericality: { greater_than: 0, only_integer: true }, allow_nil: true
  validates :user_limit, numericality: { greater_than: 0, only_integer: true }, allow_nil: true
  validates :audit_log_days, numericality: { greater_than: 0, only_integer: true }, allow_nil: true
  validates :extraction_overage_cents, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :monthly_price_cents, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :annual_price_cents, numericality: { greater_than_or_equal_to: 0, only_integer: true }

  before_validation :normalize_slug
  before_validation :set_default_position

  validate :single_default_tier
  validate :default_tier_must_be_active
  validate :system_tier_must_be_active
  validate :free_tier_guardrails
  validate :slug_immutable_for_in_use_tier, on: :update

  def paid?
    monthly_price_cents.to_i.positive? || annual_price_cents.to_i.positive?
  end

  def free?
    !paid?
  end

  private

  def normalize_slug
    self.slug = slug.to_s.parameterize if slug.present?
  end

  def set_default_position
    self.position = rank if position.nil?
  end

  def single_default_tier
    return unless default_tier?
    return unless self.class.where(default_tier: true).where.not(id: id).exists?

    errors.add(:default_tier, "can only be enabled for one tier")
  end

  def default_tier_must_be_active
    return unless default_tier?
    return if active?

    errors.add(:active, "must be enabled for the default tier")
  end

  def system_tier_must_be_active
    return unless system_tier?
    return if active?

    errors.add(:active, "must be enabled for system tiers")
  end

  def free_tier_guardrails
    return unless slug == FREE_SLUG

    errors.add(:system_tier, "must be enabled for the free tier") unless system_tier?
    errors.add(:default_tier, "must be enabled for the free tier") unless default_tier?
    errors.add(:monthly_price_cents, "must be 0 for the free tier") unless monthly_price_cents.to_i.zero?
    errors.add(:annual_price_cents, "must be 0 for the free tier") unless annual_price_cents.to_i.zero?
    errors.add(:extraction_overage_cents, "must be 0 for the free tier") unless extraction_overage_cents.to_i.zero?
  end

  def slug_immutable_for_in_use_tier
    return unless will_save_change_to_slug?

    previous_slug = slug_in_database
    return if previous_slug.blank?

    in_use = Organization.where(plan: previous_slug)
                         .or(Organization.where(pending_plan: previous_slug))
                         .exists?
    return unless in_use

    errors.add(:slug, "cannot be changed while organizations are using this tier")
  end
end
