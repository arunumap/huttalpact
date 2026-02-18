class Settings::ProfileController < ApplicationController
  def show
    @user = Current.user
  end

  def update
    @user = Current.user

    if params[:password_change].present?
      update_password
    else
      update_profile
    end
  end

  private

  def update_profile
    if @user.update(profile_params)
      log_audit("profile_updated", details: "Updated profile information")
      redirect_to settings_profile_path, notice: "Profile updated successfully."
    else
      render :show, status: :unprocessable_entity
    end
  end

  def update_password
    password_params = params.require(:password_change).permit(:current_password, :password, :password_confirmation)

    unless User.authenticate_by(email_address: @user.email_address, password: password_params[:current_password])
      @user.errors.add(:base, "Current password is incorrect")
      render :show, status: :unprocessable_entity
      return
    end

    if @user.update(password: password_params[:password], password_confirmation: password_params[:password_confirmation])
      # Destroy all other sessions to force re-login on other devices
      @user.sessions.where.not(id: Current.session.id).destroy_all
      log_audit("password_changed", details: "Password changed")
      redirect_to settings_profile_path, notice: "Password changed successfully."
    else
      render :show, status: :unprocessable_entity
    end
  end

  def profile_params
    params.require(:user).permit(:first_name, :last_name, :email_address)
  end
end
