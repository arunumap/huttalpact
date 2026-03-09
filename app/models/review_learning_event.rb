class ReviewLearningEvent < ApplicationRecord
  acts_as_tenant :organization

  DECISIONS = (ContractReviewField::STATUSES - [ "pending" ]).freeze
  ACCEPTED_DECISIONS = %w[confirmed auto_accepted].freeze
  CONTRACT_TYPES = (Contract::CONTRACT_TYPES + [ "unknown" ]).freeze
  EVIDENCE_QUALITIES = %w[strong moderate weak missing].freeze

  belongs_to :organization
  belongs_to :contract
  belongs_to :contract_review
  belongs_to :contract_review_field
  belongs_to :reviewed_by, class_name: "User", optional: true
  belongs_to :source_document, class_name: "ContractDocument", optional: true
  belongs_to :ai_usage_log, optional: true

  validates :contract_review_field_id, uniqueness: true
  validates :review_type, inclusion: { in: ContractReview::REVIEW_TYPES }
  validates :contract_type, inclusion: { in: CONTRACT_TYPES }
  validates :field_name, presence: true
  validates :field_group, inclusion: { in: ContractReviewField::FIELD_GROUPS }
  validates :decision, inclusion: { in: DECISIONS }
  validates :confidence, numericality: { in: 0..100 }, allow_nil: true
  validates :confidence_threshold, numericality: { in: 0..100 }
  validates :source_match_strategy, inclusion: { in: ContractReviewField::SOURCE_MATCH_STRATEGIES }, allow_nil: true
  validates :evidence_quality, inclusion: { in: EVIDENCE_QUALITIES }
  validates :evidence_quality_score, numericality: { in: 0..100 }, allow_nil: true
  validates :reviewed_at, presence: true
  validate :field_metadata_must_be_object
  validate :review_metadata_must_be_object
  validate :relationships_must_be_consistent

  scope :accepted, -> { where(decision: ACCEPTED_DECISIONS) }
  scope :corrected, -> { where(corrected: true) }
  scope :for_field, ->(field_name) { where(field_name:) }
  scope :for_contract_type, ->(contract_type) { where(contract_type:) }
  scope :for_review_type, ->(review_type) { where(review_type:) }
  scope :recent_first, -> { order(reviewed_at: :desc, created_at: :desc) }

  def accepted?
    ACCEPTED_DECISIONS.include?(decision)
  end

  private

  def field_metadata_must_be_object
    return if field_metadata.is_a?(Hash)

    errors.add(:field_metadata, "must be a JSON object")
  end

  def review_metadata_must_be_object
    return if review_metadata.is_a?(Hash)

    errors.add(:review_metadata, "must be a JSON object")
  end

  def relationships_must_be_consistent
    validate_contract_review_consistency
    validate_contract_consistency
    validate_source_document_consistency
  end

  def validate_contract_review_consistency
    return unless contract_review.present?

    if contract_review.contract_id != contract_id
      errors.add(:contract_review_id, "must belong to the same contract")
    end

    if contract_review.organization_id != organization_id
      errors.add(:contract_review_id, "must belong to the same organization")
    end

    return unless contract_review_field.present?
    return if contract_review_field.contract_review_id == contract_review_id

    errors.add(:contract_review_field_id, "must belong to the specified review")
  end

  def validate_contract_consistency
    return unless contract.present?
    return if contract.organization_id == organization_id

    errors.add(:contract_id, "must belong to the same organization")
  end

  def validate_source_document_consistency
    return unless source_document.present?
    return if source_document.contract_id == contract_id

    errors.add(:source_document_id, "must belong to the same contract")
  end
end
