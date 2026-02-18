require "test_helper"

class MemberRemovalServiceTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:two) # starter plan with owner(bob), admin(carol), member(dave)
    @owner = users(:two)
    @member = users(:four)
    @membership = memberships(:regular_member)
  end

  test "removes the membership" do
    assert_difference "Membership.count", -1 do
      result = MemberRemovalService.call(membership: @membership, performed_by: @owner)
      assert result.success?
    end
    assert_not Membership.exists?(@membership.id)
  end

  test "reassigns contracts uploaded by removed member to org owner" do
    # Create a contract uploaded by the member being removed
    contract = Contract.create!(
      organization: @org,
      title: "Member Contract",
      vendor_name: "Test Vendor",
      status: "active",
      contract_type: "software",
      start_date: Date.current,
      end_date: 1.year.from_now.to_date,
      uploaded_by: @member
    )

    MemberRemovalService.call(membership: @membership, performed_by: @owner)

    contract.reload
    assert_equal @owner, contract.uploaded_by
  end

  test "does not reassign contracts from other members" do
    # The org's existing contract is uploaded by the owner (bob)
    other_contract = contracts(:other_org_contract)
    assert_equal @owner, other_contract.uploaded_by

    MemberRemovalService.call(membership: @membership, performed_by: @owner)

    other_contract.reload
    assert_equal @owner, other_contract.uploaded_by
  end

  test "returns failure when trying to remove the owner" do
    owner_membership = memberships(:two)
    result = MemberRemovalService.call(membership: owner_membership, performed_by: @owner)

    assert_not result.success?
    assert_match(/owner/i, result.error)
    assert Membership.exists?(owner_membership.id)
  end

  test "creates audit log entry" do
    # Set up Current for audit logging
    Current.organization = @org
    Current.session = @owner.sessions.create!

    assert_difference "AuditLog.unscoped.count", 1 do
      MemberRemovalService.call(membership: @membership, performed_by: @owner)
    end

    audit = AuditLog.unscoped.order(created_at: :desc).first
    assert_equal "member_removed", audit.action
    assert_match @member.full_name, audit.details
  ensure
    Current.reset
  end
end
