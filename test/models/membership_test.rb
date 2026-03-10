require "test_helper"

class MembershipTest < ActiveSupport::TestCase
  test "valid membership" do
    membership = memberships(:one)
    assert membership.valid?
  end

  test "validates role inclusion" do
    membership = memberships(:one)
    membership.role = "superadmin"
    assert_not membership.valid?
  end

  test "validates uniqueness of user per organization" do
    existing = memberships(:one)
    duplicate = Membership.new(user: existing.user, organization: existing.organization, role: "member")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "is already a member of this organization"
  end

  test "owners scope returns only owners" do
    assert_includes Membership.owners, memberships(:one)
  end

  test "admins scope returns owners and admins" do
    assert_includes Membership.admins, memberships(:one)
    assert_includes Membership.admins, memberships(:admin_member)
    assert_not_includes Membership.admins, memberships(:regular_member)
  end

  # Predicate methods
  test "owner? returns true for owner role" do
    assert memberships(:one).owner?
    assert_not memberships(:admin_member).owner?
    assert_not memberships(:regular_member).owner?
  end

  test "admin? returns true for admin role" do
    assert memberships(:admin_member).admin?
    assert_not memberships(:one).admin?
    assert_not memberships(:regular_member).admin?
  end

  test "member? returns true for member role" do
    assert memberships(:regular_member).member?
    assert_not memberships(:one).member?
    assert_not memberships(:admin_member).member?
  end

  test "admin_or_owner? returns true for admin and owner roles" do
    assert memberships(:one).admin_or_owner?
    assert memberships(:admin_member).admin_or_owner?
    assert_not memberships(:regular_member).admin_or_owner?
  end

  # manageable_by? method
  test "owner can manage admin" do
    owner = memberships(:two)
    admin = memberships(:admin_member)
    assert admin.manageable_by?(owner)
  end

  test "owner can manage member" do
    owner = memberships(:two)
    member = memberships(:regular_member)
    assert member.manageable_by?(owner)
  end

  test "no one can manage the owner" do
    owner = memberships(:two)
    admin = memberships(:admin_member)
    assert_not owner.manageable_by?(admin)
    assert_not owner.manageable_by?(owner)
  end

  test "admin can manage member" do
    admin = memberships(:admin_member)
    member = memberships(:regular_member)
    assert member.manageable_by?(admin)
  end

  test "admin cannot manage another admin" do
    admin = memberships(:admin_member)
    other_admin = Membership.create!(
      user: users(:one),
      organization: organizations(:two),
      role: Membership::ADMIN_ROLE
    )
    assert_not other_admin.manageable_by?(admin)
  end

  test "member cannot manage anyone" do
    member = memberships(:regular_member)
    admin = memberships(:admin_member)
    assert_not admin.manageable_by?(member)
    assert_not member.manageable_by?(member)
  end

  # Ordered scope
  test "ordered scope puts owner first then alphabetical by name" do
    org = organizations(:two)
    ordered = org.memberships.ordered
    assert_equal Membership::OWNER_ROLE, ordered.first.role
  end

  # Orphan tracking callbacks
  test "sets orphaned_at when last membership is destroyed" do
    user = User.create!(
      email_address: "solo@example.com",
      password: "password123",
      first_name: "Solo",
      terms_accepted: "1"
    )
    org = organizations(:one)
    membership = Membership.create!(user: user, organization: org, role: Membership::MEMBER_ROLE)

    assert_nil user.reload.orphaned_at
    membership.destroy!
    assert_not_nil user.reload.orphaned_at
  end

  test "does not set orphaned_at when user still has other memberships" do
    user = users(:one)
    org = organizations(:two)
    extra = Membership.create!(user: user, organization: org, role: Membership::MEMBER_ROLE)

    extra.destroy!
    assert_nil user.reload.orphaned_at
  end

  test "clears orphaned_at when new membership is created" do
    user = User.create!(
      email_address: "returning@example.com",
      password: "password123",
      first_name: "Return",
      terms_accepted: "1"
    )
    user.update_column(:orphaned_at, 1.day.ago)

    Membership.create!(user: user, organization: organizations(:one), role: Membership::MEMBER_ROLE)
    assert_nil user.reload.orphaned_at
  end
end
