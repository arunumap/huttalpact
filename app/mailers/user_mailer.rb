class UserMailer < ApplicationMailer
  def welcome(user)
    @user = user
    @organization = user.organizations.first

    mail(
      to: @user.email_address,
      subject: "Welcome to PactBadger!"
    )
  end
end
