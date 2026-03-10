require "test_helper"

class CleanupOrphanedUsersJobTest < ActiveJob::TestCase
  setup do
    @org = organizations(:one)
  end

  test "destroys users orphaned for more than 60 days" do
    user = User.create!(
      email_address: "orphan@example.com",
      password: "password123",
      first_name: "Orphan",
      terms_accepted: "1"
    )
    user.sessions.create!
    user.update_column(:orphaned_at, 61.days.ago)

    assert_difference "User.count", -1 do
      CleanupOrphanedUsersJob.perform_now
    end

    assert_nil User.find_by(id: user.id)
    assert_equal 0, Session.where(user_id: user.id).count
  end

  test "does not destroy users orphaned for less than 60 days" do
    user = User.create!(
      email_address: "recent-orphan@example.com",
      password: "password123",
      first_name: "Recent",
      terms_accepted: "1"
    )
    user.update_column(:orphaned_at, 30.days.ago)

    assert_no_difference "User.count" do
      CleanupOrphanedUsersJob.perform_now
    end

    assert User.find_by(id: user.id)
  end

  test "does not destroy users with active memberships even if orphaned_at is set" do
    user = users(:one)
    user.update_column(:orphaned_at, 90.days.ago)

    assert_no_difference "User.count" do
      CleanupOrphanedUsersJob.perform_now
    end

    assert User.find_by(id: user.id)
  end

  test "does not destroy users without orphaned_at set" do
    user = users(:one)
    assert_nil user.orphaned_at

    assert_no_difference "User.count" do
      CleanupOrphanedUsersJob.perform_now
    end
  end

  test "handles mixed batch of orphaned and non-orphaned users" do
    orphan = User.create!(
      email_address: "old-orphan@example.com",
      password: "password123",
      first_name: "Old",
      terms_accepted: "1"
    )
    orphan.update_column(:orphaned_at, 90.days.ago)

    recent = User.create!(
      email_address: "new-orphan@example.com",
      password: "password123",
      first_name: "New",
      terms_accepted: "1"
    )
    recent.update_column(:orphaned_at, 10.days.ago)

    assert_difference "User.count", -1 do
      CleanupOrphanedUsersJob.perform_now
    end

    assert_nil User.find_by(id: orphan.id)
    assert User.find_by(id: recent.id)
  end
end
