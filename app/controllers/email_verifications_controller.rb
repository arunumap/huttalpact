class EmailVerificationsController < ApplicationController
  allow_unauthenticated_access only: :verify
  allow_unverified_access
  prepend_before_action :resume_session, only: :verify
  skip_before_action :set_tenant
  skip_before_action :set_unread_alert_count
  skip_before_action :redirect_to_onboarding
  before_action :redirect_if_verified, only: :create
  before_action :require_current_user, only: %i[show create]
  rate_limit to: 5, within: 1.minute, only: :create, with: -> { redirect_to email_verification_path, alert: "Too many verification attempts. Try again later." }

  layout "auth"

  def show
  end

  def create
    UserMailer.email_verification(Current.user).deliver_later
    redirect_to email_verification_path, notice: "Verification email sent."
  end

  def verify
    user = User.find_by_token_for(:email_verification, params[:token])
    if user.nil?
      redirect_to new_session_path, alert: "Verification link is invalid or has expired."
      return
    end

    user.verify_email!

    if Current.user.nil?
      start_new_session_for(user)
    end

    if Current.user && Current.user != user
      redirect_to root_path, notice: "That email has been verified. Please sign in with the verified account to continue."
      return
    end

    redirect_to email_verification_path, notice: "Your email has been verified. You can continue to the app."
  end

  private

  def require_current_user
    return if Current.user

    redirect_to new_session_path, alert: "Please sign in to continue."
  end

  def redirect_if_verified
    redirect_to root_path if Current.user&.email_verified?
  end
end
