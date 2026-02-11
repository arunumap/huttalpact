class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :organizations, through: :memberships
  has_many :alert_recipients, dependent: :destroy
  has_many :alerts, through: :alert_recipients
  has_many :alert_preferences, dependent: :destroy
  has_many :audit_logs
  has_many :sent_invitations, class_name: "Invitation", foreign_key: :inviter_id, dependent: :nullify

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8, maximum: 72 }, allow_nil: true
  validates :first_name, length: { maximum: 100 }, allow_nil: true
  validates :last_name, length: { maximum: 100 }, allow_nil: true

  def full_name
    [ first_name, last_name ].compact_blank.join(" ").presence || email_address
  end

  def initials
    if first_name.present?
      "#{first_name[0]}#{last_name&.[](0)}".upcase
    else
      email_address[0..1].upcase
    end
  end
end
