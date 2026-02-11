require "test_helper"

class OnboardingControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    organizations(:one).update!(onboarding_step: 0, onboarding_completed_at: nil)
  end

  test "shows organization step" do
    get onboarding_organization_path
    assert_response :success
  end

  test "updates organization and advances to contract" do
    patch onboarding_organization_path, params: { organization: { name: "New Name" } }
    assert_redirected_to onboarding_contract_path
    assert_equal 1, organizations(:one).reload.onboarding_step
  end

  test "skips contract step" do
    post onboarding_contract_skip_path
    assert_redirected_to onboarding_invite_path
    assert_equal 2, organizations(:one).reload.onboarding_step
  end

  test "creates invitation" do
    assert_difference "Invitation.count", 1 do
      post onboarding_invite_path, params: { invitation: { email: "new@example.com", role: "member" } }
    end

    assert_redirected_to onboarding_invite_path
  end

  test "completes onboarding" do
    post onboarding_complete_path
    assert_redirected_to root_path
    assert organizations(:one).reload.onboarding_complete?
  end
end
