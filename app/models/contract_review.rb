class ContractReview < ApplicationRecord
  acts_as_tenant :organization

  belongs_to :contract
  belongs_to :organization
  belongs_to :completed_by, class_name: "User", optional: true
  has_many :fields, class_name: "ContractReviewField", dependent: :destroy

  STATUSES = %w[pending in_progress completed].freeze
  REVIEW_TYPES = %w[full incremental].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :review_type, inclusion: { in: REVIEW_TYPES }
  validates :confidence_threshold, numericality: { in: 0..100 }
  validates :total_fields, numericality: { greater_than_or_equal_to: 0 }
  validates :reviewed_fields, numericality: { greater_than_or_equal_to: 0 }

  scope :pending, -> { where(status: "pending") }
  scope :in_progress, -> { where(status: "in_progress") }
  scope :completed, -> { where(status: "completed") }
  scope :active, -> { where(status: %w[pending in_progress]) }
  scope :for_contract, ->(contract) { where(contract: contract) }

  def completed?
    status == "completed"
  end

  def pending?
    status == "pending"
  end

  def in_progress?
    status == "in_progress"
  end

  def progress_percentage
    return 0 if total_fields.zero?
    (reviewed_fields.to_f / total_fields * 100).round
  end

  def all_required_fields_reviewed?
    fields.needs_review.pending.none?
  end
end
