class ExtractionOverageCharge < ApplicationRecord
  STATUS_PENDING = "pending".freeze
  STATUS_BILLED = "billed".freeze
  STATUS_FAILED = "failed".freeze
  STATUSES = [ STATUS_PENDING, STATUS_BILLED, STATUS_FAILED ].freeze

  belongs_to :organization
  belongs_to :contract, optional: true

  validates :extraction_period_start_at, presence: true
  validates :usage_position, numericality: { greater_than: 0, only_integer: true }
  validates :overage_cents, numericality: { greater_than: 0, only_integer: true }
  validates :idempotency_key, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :pending_or_failed, -> { where(status: [ STATUS_PENDING, STATUS_FAILED ]) }
  scope :stale, ->(duration = 15.minutes) { where(created_at: ..duration.ago) }

  def billed?
    status == STATUS_BILLED
  end
end
