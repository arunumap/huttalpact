class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  allow_unverified_access
  skip_before_action :set_tenant, only: :destroy
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }

  layout "auth"

  def new
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      start_new_session_for user
      track_analytics_event("login", method: "email")
      redirect_to(user.email_verified? ? after_authentication_url : email_verification_path)
    else
      redirect_to new_session_path, alert: "Try another email address or password."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
