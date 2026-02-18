require "test_helper"

class Settings::OrganizationControllerTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:two)    # Pinnacle Management, starter plan
    @owner = users(:two)          # owner of org two
    @admin = users(:three)        # admin of org two
    @member = users(:four)        # member of org two
  end

  # === Access control ===

  test "owner can view organization settings" do
    sign_in_as @owner
    get settings_organization_path
    assert_response :success
    assert_match "Organization", response.body
    assert_match @org.name, response.body
    assert_match @org.slug, response.body
  end

  test "admin can view organization settings" do
    sign_in_as @admin
    get settings_organization_path
    assert_response :success
  end

  test "member is redirected with flash" do
    sign_in_as @member
    get settings_organization_path
    assert_redirected_to root_path
    assert_match /admin|owner/i, flash[:alert]
  end

  test "unauthenticated user redirected to login" do
    get settings_organization_path
    assert_redirected_to new_session_path
  end

  # === Organization updates ===

  test "owner can update organization name" do
    sign_in_as @owner
    patch settings_organization_path, params: { organization: { name: "New Company Name", slug: @org.slug } }
    assert_redirected_to settings_organization_path
    assert_equal "Organization updated successfully.", flash[:notice]
    assert_equal "New Company Name", @org.reload.name
  end

  test "admin can update organization name" do
    sign_in_as @admin
    patch settings_organization_path, params: { organization: { name: "Admin Updated Name", slug: @org.slug } }
    assert_redirected_to settings_organization_path
    assert_equal "Admin Updated Name", @org.reload.name
  end

  test "owner can update organization slug" do
    sign_in_as @owner
    patch settings_organization_path, params: { organization: { name: @org.name, slug: "new-slug" } }
    assert_redirected_to settings_organization_path
    assert_equal "new-slug", @org.reload.slug
  end

  test "blank name shows errors" do
    sign_in_as @owner
    patch settings_organization_path, params: { organization: { name: "", slug: @org.slug } }
    assert_response :unprocessable_entity
    assert_match "can&#39;t be blank", response.body
  end

  test "invalid slug format shows errors" do
    sign_in_as @owner
    patch settings_organization_path, params: { organization: { name: @org.name, slug: "Bad Slug!" } }
    assert_response :unprocessable_entity
    assert_match "only allows lowercase letters", response.body
  end

  test "duplicate slug shows errors" do
    sign_in_as @owner
    other_org = organizations(:one)
    patch settings_organization_path, params: { organization: { name: @org.name, slug: other_org.slug } }
    assert_response :unprocessable_entity
  end

  test "member cannot update organization" do
    sign_in_as @member
    patch settings_organization_path, params: { organization: { name: "Hacked Name", slug: @org.slug } }
    assert_redirected_to root_path
    assert_not_equal "Hacked Name", @org.reload.name
  end

  test "update creates audit log" do
    sign_in_as @owner
    assert_difference "AuditLog.count", 1 do
      patch settings_organization_path, params: { organization: { name: "Audited Name", slug: @org.slug } }
    end
    assert_equal "organization_updated", AuditLog.last.action
    assert_match "name changed", AuditLog.last.details
  end

  test "no audit log when nothing changes" do
    sign_in_as @owner
    assert_no_difference "AuditLog.count" do
      patch settings_organization_path, params: { organization: { name: @org.name, slug: @org.slug } }
    end
  end
end
