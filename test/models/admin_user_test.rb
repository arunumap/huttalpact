require "test_helper"

class AdminUserTest < ActiveSupport::TestCase
  test "valid fixture admin user" do
    assert admin_users(:one).valid?
  end

  test "normalizes email address" do
    admin = AdminUser.create!(
      email_address: "  EXAMPLE@ADMIN.COM ",
      password: "password123"
    )

    assert_equal "example@admin.com", admin.email_address
  end

  test "requires unique email address" do
    duplicate = AdminUser.new(
      email_address: admin_users(:one).email_address,
      password: "password123"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email_address], "has already been taken"
  end
end
