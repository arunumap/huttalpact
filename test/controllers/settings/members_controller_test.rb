require "test_helper"

class Settings::MembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:two)  # starter plan
    @owner = users(:two)
    @admin = users(:three)
    @member = users(:four)
    @owner_membership = memberships(:two)
    @admin_membership = memberships(:admin_member)
    @member_membership = memberships(:regular_member)
  end

  # Role changes — owner as actor

  test "owner can change member role to admin" do
    sign_in_as @owner
    patch settings_member_path(@member_membership), params: { membership: { role: "admin" } }
    assert_response :redirect
    assert_equal "admin", @member_membership.reload.role
  end

  test "owner can change admin role to member" do
    sign_in_as @owner
    patch settings_member_path(@admin_membership), params: { membership: { role: "member" } }
    assert_response :redirect
    assert_equal "member", @admin_membership.reload.role
  end

  test "owner cannot change own role" do
    sign_in_as @owner
    patch settings_member_path(@owner_membership), params: { membership: { role: "member" } }
    assert_redirected_to settings_team_path
    assert_match /cannot/i, flash[:alert]
    assert_equal "owner", @owner_membership.reload.role
  end

  test "owner cannot set role to owner" do
    sign_in_as @owner
    patch settings_member_path(@member_membership), params: { membership: { role: "owner" } }
    assert_redirected_to settings_team_path
    assert_match /invalid|not allowed/i, flash[:alert]
    assert_equal "member", @member_membership.reload.role
  end

  # Role changes — admin as actor

  test "admin can change member role to admin" do
    sign_in_as @admin
    patch settings_member_path(@member_membership), params: { membership: { role: "admin" } }
    assert_response :redirect
    assert_equal "admin", @member_membership.reload.role
  end

  test "admin cannot change another admin role" do
    # Create a second admin
    second_admin = Membership.create!(
      user: users(:one),
      organization: @org,
      role: Membership::ADMIN_ROLE
    )
    sign_in_as @admin
    patch settings_member_path(second_admin), params: { membership: { role: "member" } }
    assert_redirected_to settings_team_path
    assert_match /permission/i, flash[:alert]
    assert_equal "admin", second_admin.reload.role
  end

  test "admin cannot change owner role" do
    sign_in_as @admin
    patch settings_member_path(@owner_membership), params: { membership: { role: "member" } }
    assert_redirected_to settings_team_path
    assert_match /cannot/i, flash[:alert]
    assert_equal "owner", @owner_membership.reload.role
  end

  # Role changes — member as actor (blocked)

  test "member cannot change roles" do
    sign_in_as @member
    patch settings_member_path(@admin_membership), params: { membership: { role: "member" } }
    assert_redirected_to root_path
    assert_equal "admin", @admin_membership.reload.role
  end

  # Role change audit log

  test "role change creates audit log entry" do
    sign_in_as @owner
    assert_difference "AuditLog.unscoped.count", 1 do
      patch settings_member_path(@member_membership), params: { membership: { role: "admin" } }
    end
    audit = AuditLog.unscoped.order(created_at: :desc).first
    assert_equal "member_role_changed", audit.action
  end

  # Remove member — owner as actor

  test "owner can remove member" do
    sign_in_as @owner
    assert_difference "Membership.count", -1 do
      delete settings_member_path(@member_membership)
    end
    assert_redirected_to settings_team_path
    assert_match /removed/i, flash[:notice]
  end

  test "owner can remove admin" do
    sign_in_as @owner
    assert_difference "Membership.count", -1 do
      delete settings_member_path(@admin_membership)
    end
  end

  test "owner cannot remove self" do
    sign_in_as @owner
    assert_no_difference "Membership.count" do
      delete settings_member_path(@owner_membership)
    end
    assert_redirected_to settings_team_path
    assert_match /cannot/i, flash[:alert]
  end

  # Remove member — admin as actor

  test "admin can remove member" do
    sign_in_as @admin
    assert_difference "Membership.count", -1 do
      delete settings_member_path(@member_membership)
    end
  end

  test "admin cannot remove another admin" do
    second_admin = Membership.create!(
      user: users(:one),
      organization: @org,
      role: Membership::ADMIN_ROLE
    )
    sign_in_as @admin
    assert_no_difference "Membership.count" do
      delete settings_member_path(second_admin)
    end
    assert_redirected_to settings_team_path
  end

  test "admin cannot remove owner" do
    sign_in_as @admin
    assert_no_difference "Membership.count" do
      delete settings_member_path(@owner_membership)
    end
    assert_redirected_to settings_team_path
  end

  # Remove member — member as actor (blocked)

  test "member cannot remove anyone" do
    sign_in_as @member
    assert_no_difference "Membership.count" do
      delete settings_member_path(@admin_membership)
    end
    assert_redirected_to root_path
  end

  # Removal reassigns contracts

  test "removing member reassigns their contracts to owner" do
    contract = Contract.create!(
      organization: @org,
      title: "Dave Contract",
      vendor_name: "Vendor",
      status: "active",
      contract_type: "software",
      start_date: Date.current,
      end_date: 1.year.from_now.to_date,
      uploaded_by: @member
    )
    sign_in_as @owner
    delete settings_member_path(@member_membership)
    assert_equal @owner, contract.reload.uploaded_by
  end

  # Removal audit log

  test "removal creates audit log entry" do
    sign_in_as @owner
    assert_difference "AuditLog.unscoped.count", 1 do
      delete settings_member_path(@member_membership)
    end
    audit = AuditLog.unscoped.order(created_at: :desc).first
    assert_equal "member_removed", audit.action
  end

  # Auth
  test "requires authentication" do
    patch settings_member_path(@member_membership), params: { membership: { role: "admin" } }
    assert_redirected_to new_session_path
  end

  # Cross-org protection
  test "cannot manage membership from another org" do
    sign_in_as users(:one) # owner of org one, not org two
    patch settings_member_path(@member_membership), params: { membership: { role: "admin" } }
    assert_redirected_to settings_team_path
    assert_equal "member", @member_membership.reload.role
  end
end
