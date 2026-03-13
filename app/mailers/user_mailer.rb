class UserMailer < ApplicationMailer
  def email_verification(user)
    @user = user
    @verification_url = verify_email_verification_url(token: @user.generate_token_for(:email_verification))

    mail(
      to: @user.email_address,
      subject: "Verify your email address"
    )
  end

  def welcome(user)
    @user = user
    @organization = user.organizations.first

    mail(
      to: @user.email_address,
      subject: "Welcome to PactBadger!"
    )
  end
end
