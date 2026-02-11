class Membership < ApplicationRecord
  OWNER_ROLE = "owner"
  ADMIN_ROLE = "admin"
  MEMBER_ROLE = "member"
  ROLES = [ OWNER_ROLE, ADMIN_ROLE, MEMBER_ROLE ].freeze

  belongs_to :user
  belongs_to :organization

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :organization_id, message: "is already a member of this organization" }

  scope :owners, -> { where(role: OWNER_ROLE) }
  scope :admins, -> { where(role: [ OWNER_ROLE, ADMIN_ROLE ]) }
end
