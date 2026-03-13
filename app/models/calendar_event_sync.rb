class CalendarEventSync < ApplicationRecord
  acts_as_tenant :organization

  belongs_to :calendar_connection
  belongs_to :organization
  belongs_to :source, polymorphic: true

  SYNC_STATUSES = %w[pending synced failed deleted].freeze
  MAX_RETRIES = 5

  validates :event_category, presence: true, inclusion: { in: Alert::ALERT_TYPES }
  validates :sync_status, inclusion: { in: SYNC_STATUSES }
  validates :remote_calendar_id, presence: true
  validates :source_type, uniqueness: {
    scope: [ :calendar_connection_id, :source_id, :event_category ]
  }

  scope :pending, -> { where(sync_status: "pending") }
  scope :synced, -> { where(sync_status: "synced") }
  scope :failed, -> { where(sync_status: "failed") }
  scope :deleted, -> { where(sync_status: "deleted") }
  scope :retriable, -> { failed.where("retry_count < ?", MAX_RETRIES) }
  scope :for_source, ->(source) { where(source_type: source.class.name, source_id: source.id) }

  def synced?
    sync_status == "synced"
  end

  def needs_update?(new_fingerprint)
    payload_fingerprint != new_fingerprint
  end

  def mark_synced!(remote_event_id:, fingerprint:)
    update!(
      remote_event_id: remote_event_id,
      payload_fingerprint: fingerprint,
      sync_status: "synced",
      last_synced_at: Time.current,
      last_error: nil,
      retry_count: 0
    )
  end

  def mark_failed!(error_message)
    with_lock do
      update!(
        retry_count: retry_count + 1,
        sync_status: "failed",
        last_error: error_message
      )
    end
  end

  def mark_deleted!
    update!(sync_status: "deleted", last_synced_at: Time.current)
  end

  def mark_pending!
    update!(sync_status: "pending")
  end

  def retriable?
    sync_status == "failed" && retry_count < MAX_RETRIES
  end
end
