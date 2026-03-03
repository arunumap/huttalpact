class AdminUser < ApplicationRecord
  has_secure_password

  has_many :admin_sessions, dependent: :destroy
  has_many :blog_posts, dependent: :nullify

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8, maximum: 72 }, allow_nil: true
  validates :first_name, length: { maximum: 100 }, allow_nil: true
  validates :last_name, length: { maximum: 100 }, allow_nil: true

  def full_name
    [ first_name, last_name ].compact_blank.join(" ").presence || email_address
  end
end
