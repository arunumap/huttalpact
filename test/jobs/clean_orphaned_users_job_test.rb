require "test_helper"

class CleanOrphanedUsersJobTest < ActiveJob::TestCase
  test "deletes users without organizations" do
    user = User.create!(
      email_address: "orphaned-job@example.com",
      password: "password123",
      first_name: "Orphaned",
      last_name: "User",
      terms_accepted: "1"
    )

    assert_difference("User.count", -1) do
      CleanOrphanedUsersJob.perform_now
    end

    assert_not User.exists?(user.id)
  end

  test "keeps users with organizations" do
    user = users(:one)

    assert_no_difference("User.count") do
      CleanOrphanedUsersJob.perform_now
    end

    assert User.exists?(user.id)
  end

  test "nullifies audit log users when deleting orphaned users" do
    user = User.create!(
      email_address: "orphaned-audit@example.com",
      password: "password123",
      first_name: "Audit",
      last_name: "Orphaned",
      terms_accepted: "1"
    )
    membership = Membership.create!(user: user, organization: organizations(:one), role: Membership::MEMBER_ROLE)
    contracts(:hvac_maintenance).update!(uploaded_by: user)
    audit_log = AuditLog.unscoped.create!(
      organization: organizations(:one),
      user: user,
      contract: contracts(:hvac_maintenance),
      action: "viewed",
      details: "Created during orphaned user cleanup test"
    )

    membership.destroy!

    assert_difference("User.count", -1) do
      CleanOrphanedUsersJob.perform_now
    end

    assert_nil audit_log.reload.user_id
    assert_nil contracts(:hvac_maintenance).reload.uploaded_by_id
  end
end
