require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "should get new" do
    get new_registration_path
    assert_response :success
  end

  test "should create user and organization" do
    assert_difference [ "User.count", "Organization.count", "Membership.count" ], 1 do
      post registration_path, params: {
        user: {
          first_name: "Jane",
          last_name: "Doe",
          email_address: "jane@example.com",
          password: "password123",
          password_confirmation: "password123",
          organization_name: "Jane's Properties"
        }
      }
    end

    user = User.find_by(email_address: "jane@example.com")
    assert_not_nil user
    assert_equal "Jane", user.first_name
    assert_equal "Doe", user.last_name

    org = user.organizations.first
    assert_not_nil org
    assert_equal "Jane's Properties", org.name
    assert_equal "free", org.plan

    membership = user.memberships.first
    assert_equal "owner", membership.role

    assert_redirected_to onboarding_organization_path
  end

  test "should generate org name from first name when not provided" do
    assert_difference "User.count", 1 do
      post registration_path, params: {
        user: {
          first_name: "Jane",
          email_address: "jane2@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    user = User.find_by(email_address: "jane2@example.com")
    assert_equal "Jane's Organization", user.organizations.first.name
  end

  test "should generate org name from email when no name provided" do
    assert_difference "User.count", 1 do
      post registration_path, params: {
        user: {
          email_address: "noname@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    user = User.find_by(email_address: "noname@example.com")
    assert_equal "noname's Organization", user.organizations.first.name
  end

  test "should not create user with invalid email" do
    assert_no_difference "User.count" do
      post registration_path, params: {
        user: {
          email_address: "invalid",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "should not create user with mismatched passwords" do
    assert_no_difference "User.count" do
      post registration_path, params: {
        user: {
          email_address: "mismatch@example.com",
          password: "password123",
          password_confirmation: "differentpassword"
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "should not create user with duplicate email" do
    assert_no_difference "User.count" do
      post registration_path, params: {
        user: {
          email_address: users(:one).email_address,
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "should not create user with short password" do
    assert_no_difference "User.count" do
      post registration_path, params: {
        user: {
          first_name: "Short",
          email_address: "short@example.com",
          password: "abc",
          password_confirmation: "abc"
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "authenticated user is redirected from new registration" do
    sign_in_as(users(:one))
    get new_registration_path
    assert_redirected_to root_path
  end

  test "authenticated user is redirected from create registration" do
    sign_in_as(users(:one))
    assert_no_difference "User.count" do
      post registration_path, params: {
        user: {
          first_name: "Ghost",
          email_address: "ghost@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end
    assert_redirected_to root_path
  end

  test "invitation signup joins existing organization" do
    organization = organizations(:one)
    invitation = invitations(:pending)

    assert_difference "User.count", 1 do
      assert_difference "Membership.count", 1 do
        post registration_path, params: {
          token: invitation.token,
          user: {
            first_name: "Invited",
            last_name: "User",
            password: "password123",
            password_confirmation: "password123"
          }
        }
      end
    end

    user = User.find_by(email_address: invitation.email)
    assert_not_nil user
    assert user.organizations.include?(organization)
    assert invitation.reload.accepted_at.present?
  end
end
