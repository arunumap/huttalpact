require "test_helper"

class AdminSessionTest < ActiveSupport::TestCase
  setup do
    @admin_user = admin_users(:one)
  end

  test "belongs to admin user" do
    session = @admin_user.admin_sessions.create!
    assert_equal @admin_user, session.admin_user
  end

  test "expired? returns false for fresh session" do
    session = @admin_user.admin_sessions.create!
    assert_not session.expired?
  end

  test "expired? returns true for old session" do
    session = @admin_user.admin_sessions.create!
    session.update_column(:created_at, 31.days.ago)
    assert session.expired?
  end

  test "active scope returns only non-expired sessions" do
    fresh = @admin_user.admin_sessions.create!
    old = @admin_user.admin_sessions.create!
    old.update_column(:created_at, 31.days.ago)

    assert_includes AdminSession.active, fresh
    assert_not_includes AdminSession.active, old
  end
end
