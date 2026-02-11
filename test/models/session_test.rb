require "test_helper"

class SessionTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "belongs to user" do
    session = @user.sessions.create!
    assert_equal @user, session.user
  end

  test "expired? returns false for fresh session" do
    session = @user.sessions.create!
    assert_not session.expired?
  end

  test "expired? returns true for old session" do
    session = @user.sessions.create!
    session.update_column(:created_at, 31.days.ago)
    assert session.expired?
  end

  test "expired? returns false at just under TTL boundary" do
    session = @user.sessions.create!
    session.update_column(:created_at, 30.days.ago + 1.second)
    assert_not session.expired?
  end

  test "active scope returns only non-expired sessions" do
    fresh = @user.sessions.create!
    old = @user.sessions.create!
    old.update_column(:created_at, 31.days.ago)

    assert_includes Session.active, fresh
    assert_not_includes Session.active, old
  end

  test "expired scope returns only expired sessions" do
    fresh = @user.sessions.create!
    old = @user.sessions.create!
    old.update_column(:created_at, 31.days.ago)

    assert_not_includes Session.expired, fresh
    assert_includes Session.expired, old
  end
end
