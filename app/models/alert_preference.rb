class AlertPreference < ApplicationRecord
  acts_as_tenant :organization

  belongs_to :user
  belongs_to :organization

  validates :user_id, uniqueness: { scope: :organization_id }
  validates :days_before_renewal, numericality: { only_integer: true, greater_than: 0 }
  validates :days_before_expiry, numericality: { only_integer: true, greater_than: 0 }

  def self.for(user, organization)
    find_or_initialize_by(user: user, organization: organization)
  end
end
