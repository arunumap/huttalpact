require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  setup do
    @user = users(:one)
    @organization = organizations(:one)
  end

  test "welcome email sends to the correct user" do
    email = UserMailer.welcome(@user)
    assert_equal [ @user.email_address ], email.to
  end

  test "welcome email from address is set" do
    email = UserMailer.welcome(@user)
    assert_equal [ "notifications@pactbadger.com" ], email.from
  end

  test "welcome email has correct subject" do
    email = UserMailer.welcome(@user)
    assert_equal "Welcome to PactBadger!", email.subject
  end

  test "html body contains user first name" do
    email = UserMailer.welcome(@user)
    assert_match "Alice", email.html_part.body.to_s
  end

  test "html body contains organization name" do
    email = UserMailer.welcome(@user)
    assert_match @organization.name, email.html_part.body.to_s
  end

  test "html body contains dashboard link" do
    email = UserMailer.welcome(@user)
    assert_match "dashboard", email.html_part.body.to_s
  end

  test "html body contains feature highlights" do
    email = UserMailer.welcome(@user)
    body = email.html_part.body.to_s
    assert_match "Upload contracts", body
    assert_match "AI-powered extraction", body
    assert_match "Smart alerts", body
  end

  test "text body contains user first name" do
    email = UserMailer.welcome(@user)
    assert_match "Alice", email.text_part.body.to_s
  end

  test "text body contains organization name" do
    email = UserMailer.welcome(@user)
    assert_match @organization.name, email.text_part.body.to_s
  end

  test "text body contains dashboard URL" do
    email = UserMailer.welcome(@user)
    assert_match "dashboard", email.text_part.body.to_s
  end

  test "text body contains feature highlights" do
    email = UserMailer.welcome(@user)
    body = email.text_part.body.to_s
    assert_match "Upload contracts", body
    assert_match "AI-powered extraction", body
    assert_match "Smart alerts", body
  end

  test "welcome email for user without organization" do
    user = User.new(
      email_address: "solo@example.com",
      first_name: "Solo",
      password: "password123"
    )
    # User has no organizations
    email = UserMailer.welcome(user)

    assert_equal [ "solo@example.com" ], email.to
    assert_no_match "you've joined", email.html_part.body.to_s
    assert_no_match "you've joined", email.text_part.body.to_s
  end

  test "email verification email sends to the correct user" do
    email = UserMailer.email_verification(@user)
    assert_equal [ @user.email_address ], email.to
    assert_equal "Verify your email address", email.subject
  end

  test "email verification email includes verification link" do
    @user.update!(email_verified_at: nil)
    email = UserMailer.email_verification(@user)

    assert_match "/email_verification/verify/", email.html_part.body.to_s
    assert_match "/email_verification/verify/", email.text_part.body.to_s
  end
end
