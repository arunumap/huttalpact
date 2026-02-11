class Contract < ApplicationRecord
  acts_as_tenant :organization

  belongs_to :organization, counter_cache: true
  belongs_to :uploaded_by, class_name: "User", optional: true
  has_many :contract_documents, dependent: :destroy
  has_many :key_clauses, dependent: :destroy
  has_many :alerts, dependent: :destroy
  has_many :audit_logs, dependent: :nullify

  normalizes :vendor_name, with: ->(v) { v.strip.squeeze(" ") }

  validates :title, presence: true, length: { maximum: 255 }, unless: :draft?
  validates :title, length: { maximum: 255 }, if: :draft?
  validates :vendor_name, length: { maximum: 255 }, allow_nil: true
  validates :status, inclusion: { in: %w[draft active expiring_soon expired renewed cancelled archived] }
  validates :contract_type, inclusion: { in: %w[lease service_agreement maintenance insurance software other] }, allow_blank: true
  validates :direction, inclusion: { in: %w[inbound outbound] }
  validates :monthly_value, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :total_value, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :notice_period_days, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :renewal_term, inclusion: { in: %w[month-to-month annual 2-year custom] }, allow_blank: true
  validates :extraction_status, inclusion: { in: %w[pending processing completed failed] }
  validates :notes, length: { maximum: 10_000 }, allow_nil: true

  validate :within_contract_limit, on: :create, unless: :draft?
  validate :within_contract_limit_on_reactivation, on: :update
  validate :end_date_after_start_date
  validate :renewal_date_after_start_date

  scope :active, -> { where(status: "active") }
  scope :expiring_soon, -> { where(status: "expiring_soon") }
  scope :expired, -> { where(status: "expired") }
  scope :archived, -> { where(status: "archived") }
  scope :not_archived, -> { where.not(status: %w[archived draft]) }
  scope :draft, -> { where(status: "draft") }
  scope :not_draft, -> { where.not(status: "draft") }
  scope :inbound, -> { where(direction: "inbound") }
  scope :outbound, -> { where(direction: "outbound") }
  scope :by_type, ->(type) { where(contract_type: type) }
  scope :by_status, ->(status) { where(status: status) }
  scope :by_direction, ->(direction) { where(direction: direction) }
  scope :search, ->(query) {
    where("title ILIKE :q OR vendor_name ILIKE :q", q: "%#{sanitize_sql_like(query)}%")
  }
  scope :expiring_within, ->(days) { where(end_date: ..days.days.from_now.to_date).where.not(status: %w[expired archived]) }
  scope :renewal_within, ->(days) { where(next_renewal_date: ..days.days.from_now.to_date) }

  STATUSES = %w[draft active expiring_soon expired renewed cancelled archived].freeze
  CONTRACT_TYPES = %w[lease service_agreement maintenance insurance software other].freeze
  RENEWAL_TERMS = %w[month-to-month annual 2-year custom].freeze
  DIRECTIONS = %w[inbound outbound].freeze
  EXTRACTION_STATUSES = %w[pending processing completed failed].freeze

  INACTIVE_STATUSES = %w[archived cancelled expired].freeze
  DRAFT_STATUSES = %w[draft].freeze
  ACTIVE_STATUSES = (STATUSES - INACTIVE_STATUSES - DRAFT_STATUSES).freeze

  def status_label
    status.titleize.gsub("_", " ")
  end

  def contract_type_label
    contract_type&.titleize&.gsub("_", " ")
  end

  def direction_label
    direction == "inbound" ? "Revenue" : "Expense"
  end

  def inbound?
    direction == "inbound"
  end

  def outbound?
    direction == "outbound"
  end

  def draft?
    status == "draft"
  end

  def days_until_expiry
    return nil unless end_date
    (end_date - Date.current).to_i
  end

  def days_until_renewal
    return nil unless next_renewal_date
    (next_renewal_date - Date.current).to_i
  end

  private

  def within_contract_limit
    return unless organization
    return unless organization.at_contract_limit?

    errors.add(:base, "Contract limit reached for the #{organization.plan_display_name} plan. Please upgrade to add more contracts.")
  end

  def within_contract_limit_on_reactivation
    return unless organization
    return unless status_changed?
    return unless INACTIVE_STATUSES.include?(status_was)
    return unless ACTIVE_STATUSES.include?(status)
    return unless organization.at_contract_limit?

    errors.add(:base, "Contract limit reached for the #{organization.plan_display_name} plan. Cannot reactivate this contract.")
  end

  def end_date_after_start_date
    return unless start_date.present? && end_date.present?
    return if end_date > start_date

    errors.add(:end_date, "must be after the start date")
  end

  def renewal_date_after_start_date
    return unless start_date.present? && next_renewal_date.present?
    return if next_renewal_date >= start_date

    errors.add(:next_renewal_date, "must be on or after the start date")
  end
end
