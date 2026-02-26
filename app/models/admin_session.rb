class AdminSession < ApplicationRecord
  SESSION_TTL = 30.days

  belongs_to :admin_user

  scope :active, -> { where("created_at > ?", SESSION_TTL.ago) }
  scope :expired, -> { where("created_at <= ?", SESSION_TTL.ago) }

  def expired?
    created_at <= SESSION_TTL.ago
  end
end
