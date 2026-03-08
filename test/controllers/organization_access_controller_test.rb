require "test_helper"

class OrganizationAccessControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get organization_access_path

    assert_redirected_to new_session_path
  end

  test "orgless user sees guidance and delete action" do
    user = User.create!(
      email_address: "orgless-guidance@example.com",
      password: "password123",
      first_name: "Orgless",
      last_name: "Guidance",
      terms_accepted: "1"
    )
    sign_in_as(user)

    get organization_access_path

    assert_response :success
    assert_match "not associated with any organizations", response.body
    assert_match "support@pactbadger.com", response.body
    assert_select "form[action='#{organization_access_path}']"
  end

  test "user with an organization is redirected away" do
    sign_in_as(users(:one))

    get organization_access_path

    assert_redirected_to root_path
  end

  test "orgless user can delete their user record" do
    user = User.create!(
      email_address: "orgless-delete@example.com",
      password: "password123",
      first_name: "Delete",
      last_name: "Me",
      terms_accepted: "1"
    )
    sign_in_as(user)
    session_id = Current.session.id

    assert_difference("User.count", -1) do
      assert_difference("Session.count", -1) do
        delete organization_access_path
      end
    end

    assert_redirected_to root_path
    assert_match "account has been deleted", flash[:notice]
    assert_nil Session.find_by(id: session_id)
    assert_empty cookies[:session_id]
  end
end
