class Settings::AlertsController < ApplicationController
  def show
    @alert_preference = AlertPreference.for(Current.user, Current.organization)
  end

  def update
    @alert_preference = AlertPreference.for(Current.user, Current.organization)

    if @alert_preference.update(alert_preference_params)
      enqueue_alert_regeneration
      redirect_to settings_alerts_path, notice: "Alert preferences updated."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def alert_preference_params
    params.require(:alert_preference).permit(
      :email_enabled, :in_app_enabled,
      :days_before_renewal, :days_before_expiry,
      :days_before_option_exercise, :days_before_rent_escalation,
      :days_before_cam_reconciliation, :days_before_milestone
    )
  end

  def enqueue_alert_regeneration
    Current.organization.contracts.where(status: Contract::ACTIVE_STATUSES).find_each do |contract|
      GenerateContractAlertsJob.perform_later(contract.id)
    end

    Current.user.calendar_connections.where(organization: Current.organization).active.find_each do |connection|
      SyncCalendarEventsJob.perform_later(connection.id)
    end
  end
end
