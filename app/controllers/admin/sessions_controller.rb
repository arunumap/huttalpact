class Admin::SessionsController < Admin::BaseController
  allow_unauthenticated_admin_access only: %i[new create]
  rate_limit to: 5, within: 5.minutes, only: :create, with: -> { redirect_to new_admin_session_path, alert: "Try again later." }

  layout "admin_auth"

  def new
  end

  def create
    if admin_user = AdminUser.authenticate_by(params.permit(:email_address, :password))
      start_admin_session_for(admin_user)
      redirect_to after_admin_authentication_url
    else
      redirect_to new_admin_session_path, alert: "Try another email address or password."
    end
  end

  def destroy
    terminate_admin_session
    redirect_to new_admin_session_path, status: :see_other
  end
end
