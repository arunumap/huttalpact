require "test_helper"

class AuthFlowTest < ActionDispatch::IntegrationTest
  test "full registration and login flow" do
    # Register a new user
    post registration_path, params: {
      user: {
        first_name: "Integration",
        last_name: "Test",
        email_address: "integration@example.com",
        password: "securepass1",
        password_confirmation: "securepass1",
        organization_name: "Integration Org"
      }
    }
    assert_redirected_to onboarding_organization_path
    follow_redirect!
    assert_response :success

    # Log out
    delete session_path
    assert_redirected_to new_session_path

    # Log back in
    post session_path, params: {
      email_address: "integration@example.com",
      password: "securepass1"
    }
    assert_redirected_to root_path
    follow_redirect!
    assert_redirected_to onboarding_organization_path
    follow_redirect!
    assert_response :success
  end

  test "unauthenticated user sees landing page" do
    get root_path
    assert_response :success
  end

  test "unauthenticated user cannot access dashboard" do
    get dashboard_path
    assert_redirected_to new_session_path
  end

  test "login then logout prevents access" do
    sign_in_as(users(:one))

    get dashboard_path
    assert_response :success

    delete session_path
    assert_redirected_to new_session_path

    get dashboard_path
    assert_redirected_to new_session_path
  end

  test "tenant isolation - user only sees own contracts" do
    # User one belongs to org one, user two to org two
    sign_in_as(users(:one))

    get contracts_path
    assert_response :success
    # Should see org one's contracts (HVAC, landscaping, etc.) but not org two's
    assert_match "HVAC Maintenance", response.body
    assert_no_match "Pinnacle", response.body
  end
end
