class ContractReviewField < ApplicationRecord
  belongs_to :contract_review
  belongs_to :source_document, class_name: "ContractDocument", optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true
  has_one :learning_event, class_name: "ReviewLearningEvent", dependent: :destroy

  STATUSES = %w[pending confirmed edited not_found not_applicable auto_accepted].freeze
  FIELD_GROUPS = %w[core dates financial lease_space cam ti escalations options milestones clauses].freeze
  SOURCE_MATCH_STRATEGIES = %w[exact fuzzy anchor none].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :field_group, inclusion: { in: FIELD_GROUPS }
  validates :field_name, presence: true
  validates :display_name, presence: true
  validates :confidence, numericality: { in: 0..100 }, allow_nil: true
  validates :source_match_strategy, inclusion: { in: SOURCE_MATCH_STRATEGIES }, allow_nil: true

  scope :pending, -> { where(status: "pending") }
  scope :confirmed, -> { where(status: "confirmed") }
  scope :edited, -> { where(status: "edited") }
  scope :auto_accepted, -> { where(status: "auto_accepted") }
  scope :not_found, -> { where(status: "not_found") }
  scope :not_applicable, -> { where(status: "not_applicable") }
  scope :reviewed, -> { where.not(status: "pending") }
  scope :needs_review, -> { where(needs_review: true) }
  scope :confident, -> { where(needs_review: false) }
  scope :by_group, ->(group) { where(field_group: group) }
  scope :ordered, -> { order(:field_group, :position) }

  def reviewed?
    status != "pending"
  end

  def final_value
    case status
    when "confirmed", "auto_accepted"
      extracted_value
    when "edited"
      user_value
    when "not_found", "not_applicable"
      nil
    else
      extracted_value
    end
  end
end
