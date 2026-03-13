require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

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
          organization_name: "Jane's Properties",
          terms_accepted: "1"
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
    assert_nil user.email_verified_at

    assert_redirected_to email_verification_path
  end

  test "should generate org name from first name when not provided" do
    assert_difference "User.count", 1 do
      post registration_path, params: {
        user: {
          first_name: "Jane",
          email_address: "jane2@example.com",
          password: "password123",
          password_confirmation: "password123",
          terms_accepted: "1"
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
          password_confirmation: "password123",
          terms_accepted: "1"
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
            password_confirmation: "password123",
            terms_accepted: "1"
          }
        }
      end
    end

    user = User.find_by(email_address: invitation.email)
    assert_not_nil user
    assert user.organizations.include?(organization)
    assert user.email_verified?
    assert invitation.reload.accepted_at.present?
  end

  test "email verification email is sent on successful registration" do
    assert_enqueued_emails 1 do
      post registration_path, params: {
        user: {
          first_name: "Welcome",
          last_name: "Test",
          email_address: "welcometest@example.com",
          password: "password123",
          password_confirmation: "password123",
          organization_name: "Welcome Org",
          terms_accepted: "1"
        }
      }
    end
  end

  test "welcome email is sent for invitation signup" do
    invitation = invitations(:pending)

    assert_enqueued_emails 1 do
      post registration_path, params: {
        token: invitation.token,
        user: {
          first_name: "Invited",
          last_name: "Welcome",
          password: "password123",
          password_confirmation: "password123",
          terms_accepted: "1"
        }
      }
    end
  end

  test "welcome email is not sent on failed registration" do
    assert_enqueued_emails 0 do
      post registration_path, params: {
        user: {
          email_address: "invalid",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end
  end

  test "should not create user without terms acceptance" do
    assert_no_difference "User.count" do
      post registration_path, params: {
        user: {
          first_name: "No",
          last_name: "Terms",
          email_address: "noterms@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "should store terms_accepted_at timestamp on successful registration" do
    post registration_path, params: {
      user: {
        first_name: "Timestamp",
        last_name: "Test",
        email_address: "timestamp@example.com",
        password: "password123",
        password_confirmation: "password123",
        terms_accepted: "1"
      }
    }

    user = User.find_by(email_address: "timestamp@example.com")
    assert_not_nil user
    assert_not_nil user.terms_accepted_at
  end

  test "ads landing signup creates account without extra click-through" do
    assert_difference [ "User.count", "Organization.count", "Membership.count" ], 1 do
      post registration_path, params: {
        source: "ads_contracts_landing",
        utm_source: "google",
        utm_campaign: "pm_search",
        user: {
          first_name: "Paula",
          last_name: "Manager",
          organization_name: "Oak Property Management",
          email_address: "paula.manager@example.com",
          password: "password123",
          password_confirmation: "password123",
          terms_accepted: "1"
        }
      }
    end

    assert_redirected_to email_verification_path
    user = User.find_by(email_address: "paula.manager@example.com")
    assert_not_nil user
    assert_equal "Oak Property Management", user.organizations.first.name
  end

  test "ads landing signup failures re-render landing page with inline errors" do
    assert_no_difference "User.count" do
      post registration_path, params: {
        source: "ads_contracts_landing",
        utm_source: "google",
        user: {
          first_name: "Pat",
          last_name: "Ops",
          organization_name: "Downtown Properties",
          email_address: "invalid",
          password: "password123",
          password_confirmation: "password123",
          terms_accepted: "1"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "h2", /Create your free account/
    assert_select "form[action='#{registration_path}']"
    assert_select "input[name='source'][value='ads_contracts_landing']", count: 1
    assert_select "input[name='utm_source'][value='google']", count: 1
    assert_select "input[name='user[organization_name]'][value='Downtown Properties']", count: 1
  end
end
