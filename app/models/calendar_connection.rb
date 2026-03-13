class CalendarConnection < ApplicationRecord
  acts_as_tenant :organization

  belongs_to :user
  belongs_to :organization
  has_one :calendar_preference, dependent: :destroy
  has_many :calendar_event_syncs, dependent: :destroy

  PROVIDERS = %w[google microsoft].freeze
  STATUSES = %w[active expired revoked error].freeze

  encrypts :access_token
  encrypts :refresh_token

  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :status, inclusion: { in: STATUSES }
  validates :access_token, presence: true
  validates :provider, uniqueness: { scope: [ :user_id, :organization_id ] }

  scope :active, -> { where(status: "active") }
  scope :google, -> { where(provider: "google") }
  scope :microsoft, -> { where(provider: "microsoft") }
  scope :needs_token_refresh, -> {
    where(status: "active")
      .where("token_expires_at IS NOT NULL AND token_expires_at <= ?", 5.minutes.from_now)
  }

  def active?
    status == "active"
  end

  def token_expired?
    token_expires_at.present? && token_expires_at <= Time.current
  end

  def token_expiring_soon?
    token_expires_at.present? && token_expires_at <= 5.minutes.from_now
  end

  def google?
    provider == "google"
  end

  def microsoft?
    provider == "microsoft"
  end

  def update_tokens!(access_token:, refresh_token: nil, expires_at: nil)
    attrs = { access_token: access_token, token_expires_at: expires_at, status: "active", last_error: nil }
    attrs[:refresh_token] = refresh_token if refresh_token.present?
    update!(attrs)
  end

  def mark_error!(message)
    update!(status: "error", last_error: message)
  end

  def mark_revoked!
    update!(status: "revoked")
  end

  def sync_preference
    calendar_preference&.sync_enabled? ? calendar_preference : nil
  end
end
