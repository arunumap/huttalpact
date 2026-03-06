class BulkDeleteOperation < ApplicationRecord
  acts_as_tenant :organization

  belongs_to :organization
  belongs_to :user

  STATUS_QUEUED = "queued".freeze
  STATUS_PROCESSING = "processing".freeze
  STATUS_COMPLETED = "completed".freeze
  STATUS_COMPLETED_WITH_ERRORS = "completed_with_errors".freeze
  STATUS_FAILED = "failed".freeze

  STATUSES = [
    STATUS_QUEUED,
    STATUS_PROCESSING,
    STATUS_COMPLETED,
    STATUS_COMPLETED_WITH_ERRORS,
    STATUS_FAILED
  ].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :requested_count, :processed_count, :deleted_count, :failed_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :in_progress, -> { where(status: [ STATUS_QUEUED, STATUS_PROCESSING ]) }
  scope :recent_first, -> { order(created_at: :desc) }

  def in_progress?
    status.in?([ STATUS_QUEUED, STATUS_PROCESSING ])
  end
end
