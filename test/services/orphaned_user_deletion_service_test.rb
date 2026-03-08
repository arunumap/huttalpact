require "test_helper"

class OrphanedUserDeletionServiceTest < ActiveSupport::TestCase
  test "deletes a user without organizations and nullifies optional references" do
    user = User.create!(
      email_address: "orphaned-service@example.com",
      password: "password123",
      first_name: "Service",
      last_name: "Orphaned",
      terms_accepted: "1"
    )
    membership = Membership.create!(user: user, organization: organizations(:one), role: Membership::MEMBER_ROLE)
    contracts(:landscaping).update!(uploaded_by: user)
    audit_log = AuditLog.unscoped.create!(
      organization: organizations(:one),
      user: user,
      contract: contracts(:landscaping),
      action: "viewed",
      details: "Created during orphaned user deletion service test"
    )

    membership.destroy!

    OrphanedUserDeletionService.new(user).delete!

    assert_not User.exists?(user.id)
    assert_nil audit_log.reload.user_id
    assert_nil contracts(:landscaping).reload.uploaded_by_id
  end

  test "raises when the user still has an organization" do
    user = users(:one)

    error = assert_raises(ArgumentError) do
      OrphanedUserDeletionService.new(user).delete!
    end

    assert_match "still associated", error.message
  end
end
