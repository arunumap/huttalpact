class Invitation < ApplicationRecord
  belongs_to :organization
  belongs_to :inviter, class_name: "User"

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, inclusion: { in: Membership::ROLES }
  validates :token, presence: true, uniqueness: true
  validates :email, uniqueness: {
    scope: :organization_id,
    conditions: -> { where(accepted_at: nil) },
    case_sensitive: false,
    message: "has already been invited"
  }

  before_validation :normalize_email
  before_validation :set_defaults, on: :create
  before_validation :generate_token, on: :create

  scope :pending, -> { where(accepted_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :expired, -> { where(accepted_at: nil).where("expires_at <= ?", Time.current) }

  def accept!
    update!(accepted_at: Time.current)
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end

  def set_defaults
    self.role ||= Membership::MEMBER_ROLE
    self.expires_at ||= 14.days.from_now
  end

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(32)
  end
end
