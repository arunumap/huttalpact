class ContractReviewField < ApplicationRecord
  acts_as_tenant :organization

  SOURCE_TYPES = %w[direct derived app_managed].freeze
  READINESS_BUCKETS = %w[pending looks_good needs_review blocked].freeze
  REVIEW_STATUSES = %w[pending confirmed edited not_found not_applicable].freeze

  belongs_to :contract_review
  belongs_to :contract
  belongs_to :organization
  belongs_to :source_document, class_name: "ContractDocument", optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true

  has_many :contract_review_conflicts, dependent: :destroy
  has_many :contract_review_field_events, dependent: :destroy

  before_validation :assign_parent_references
  before_validation :hydrate_catalog_metadata

  validates :field_key, presence: true
  validates :field_family, inclusion: { in: ReviewFieldCatalog::FIELD_FAMILIES }
  validates :classification, inclusion: { in: ReviewFieldCatalog::CLASSIFICATIONS }
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :readiness_bucket, inclusion: { in: READINESS_BUCKETS }
  validates :review_status, inclusion: { in: REVIEW_STATUSES }
  validates :field_index, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :field_index, presence: true, if: :repeatable?
  validates :field_key, uniqueness: { scope: :contract_review_id, message: "already exists for this review" }, unless: :repeatable?
  validates :field_index, uniqueness: { scope: %i[contract_review_id field_key], message: "already exists for this repeatable field" }, if: :repeatable?

  scope :gating, -> { where(gates_activation: true) }
  scope :pending_readiness, -> { where(readiness_bucket: "pending") }
  scope :looks_good, -> { where(readiness_bucket: "looks_good") }
  scope :needs_review, -> { where(readiness_bucket: "needs_review") }
  scope :blocked, -> { where(readiness_bucket: "blocked") }
  scope :pending_review, -> { where(review_status: "pending") }
  scope :reviewed, -> { where.not(reviewed_at: nil) }
  scope :for_field, ->(field_key) { where(field_key: field_key.to_s) }

  validate :field_key_in_catalog
  validate :organization_matches_review
  validate :contract_matches_review
  validate :source_document_matches_contract

  after_save :refresh_review_summary
  after_destroy :refresh_review_summary

  def reviewed?
    review_status != "pending"
  end

  def effective_value
    approved_value.nil? ? extracted_value : approved_value
  end

  private

  def assign_parent_references
    self.contract ||= contract_review&.contract
    self.organization ||= contract_review&.organization || contract&.organization
  end

  def hydrate_catalog_metadata
    definition = catalog_definition
    return unless definition

    self.field_key = definition.key
    self.field_family = definition.field_family
    self.classification = definition.classification
    self.source_type = definition.source_type
    self.repeatable = definition.repeatable?
    self.gates_activation = definition.blocks_activation?
    self.derived_dependency_keys = definition.dependencies
    self.alert_family_keys = definition.alert_families
    self.field_index = nil unless repeatable?
  end

  def field_key_in_catalog
    return if field_key.blank?
    return if catalog_definition.present?

    errors.add(:field_key, "is not included in the review field catalog")
  end

  def organization_matches_review
    return if contract_review.blank? || organization.blank?
    return if contract_review.organization_id == organization_id

    errors.add(:organization, "must match the contract review organization")
  end

  def contract_matches_review
    return if contract_review.blank? || contract.blank?
    return if contract_review.contract_id == contract_id

    errors.add(:contract, "must match the contract review contract")
  end

  def source_document_matches_contract
    return if source_document.blank? || contract.blank?
    return if source_document.contract_id == contract_id

    errors.add(:source_document, "must belong to the same contract")
  end

  def refresh_review_summary
    contract_review&.refresh_summary!
  end

  def catalog_definition
    return if field_key.blank?

    @catalog_definition ||= ReviewFieldCatalog.fetch(field_key)
  rescue KeyError
    nil
  end
end
