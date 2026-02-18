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
  scope :ordered, -> { joins(:user).order(Arel.sql("CASE memberships.role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 ELSE 2 END"), "users.first_name ASC", "users.last_name ASC") }

  def owner?
    role == OWNER_ROLE
  end

  def admin?
    role == ADMIN_ROLE
  end

  def member?
    role == MEMBER_ROLE
  end

  def admin_or_owner?
    owner? || admin?
  end

  # Can the given actor_membership manage (edit role / remove) this membership?
  def manageable_by?(actor_membership)
    return false if owner?                        # no one manages the owner
    return false unless actor_membership.admin_or_owner? # only admins+ can manage
    return true if actor_membership.owner?         # owner can manage anyone (except owner, handled above)
    member?                                        # admins can only manage members
  end
end
