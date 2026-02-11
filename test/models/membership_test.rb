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
  end
end
