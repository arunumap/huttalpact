class ExtractionFeedback < ApplicationRecord
  RATINGS = %w[positive negative].freeze

  acts_as_tenant(:organization)

  belongs_to :contract
  belongs_to :user
  belongs_to :organization
  belongs_to :ai_usage_log, optional: true

  validates :rating, presence: true, inclusion: { in: RATINGS }
  validates :user_id, uniqueness: { scope: :contract_id, message: "has already submitted feedback for this contract" }

  scope :positive, -> { where(rating: "positive") }
  scope :negative, -> { where(rating: "negative") }
  scope :recent, -> { order(created_at: :desc) }
  scope :in_period, ->(start_time, end_time) { where(created_at: start_time..end_time) }
end
