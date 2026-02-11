class AlertPreferencesController < ApplicationController
  def show
    @alert_preference = AlertPreference.for(Current.user, Current.organization)
  end

  def update
    @alert_preference = AlertPreference.for(Current.user, Current.organization)

    if @alert_preference.update(alert_preference_params)
      redirect_to alert_preference_path, notice: "Alert preferences updated."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def alert_preference_params
    params.require(:alert_preference).permit(
      :email_enabled, :in_app_enabled,
      :days_before_renewal, :days_before_expiry
    )
  end
end
