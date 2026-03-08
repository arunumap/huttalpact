class ContractReviewConflict < ApplicationRecord
  acts_as_tenant :organization

  CONFLICT_TYPES = %w[
    value_mismatch
    missing_extracted_value
    unexpected_extracted_value
    derived_dependency_missing
    source_evidence_changed
  ].freeze
  STATUSES = %w[open resolved dismissed].freeze

  belongs_to :contract_review
  belongs_to :contract_review_field
  belongs_to :contract
  belongs_to :organization
  belongs_to :resolved_by, class_name: "User", optional: true

  before_validation :assign_parent_references
  before_validation :hydrate_alert_family_keys

  validates :conflict_type, inclusion: { in: CONFLICT_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :summary, presence: true, length: { maximum: 255 }

  scope :open, -> { where(status: "open") }
  scope :resolved, -> { where(status: "resolved") }
  scope :dismissed, -> { where(status: "dismissed") }
  scope :blocking, -> { where(blocks_activation: true) }

  validate :field_matches_review
  validate :field_matches_contract
  validate :field_matches_organization

  after_save :refresh_review_summary
  after_destroy :refresh_review_summary

  def open?
    status == "open"
  end

  def resolved?
    status == "resolved"
  end

  private

  def assign_parent_references
    self.contract_review ||= contract_review_field&.contract_review
    self.contract ||= contract_review_field&.contract || contract_review&.contract
    self.organization ||= contract_review_field&.organization || contract_review&.organization || contract&.organization
  end

  def hydrate_alert_family_keys
    return if contract_review_field.blank?
    return unless alert_family_keys.blank?

    self.alert_family_keys = contract_review_field.alert_family_keys
  end

  def field_matches_review
    return if contract_review_field.blank? || contract_review.blank?
    return if contract_review_field.contract_review_id == contract_review_id

    errors.add(:contract_review, "must match the conflict field review")
  end

  def field_matches_contract
    return if contract_review_field.blank? || contract.blank?
    return if contract_review_field.contract_id == contract_id

    errors.add(:contract, "must match the conflict field contract")
  end

  def field_matches_organization
    return if contract_review_field.blank? || organization.blank?
    return if contract_review_field.organization_id == organization_id

    errors.add(:organization, "must match the conflict field organization")
  end

  def refresh_review_summary
    contract_review&.refresh_summary!
  end
end
