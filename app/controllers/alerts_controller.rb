class AlertsController < ApplicationController
  include Pagy::Backend
  include ActionView::RecordIdentifier

  before_action :set_alert, only: %i[acknowledge snooze]

  def index
    alerts = Alert.visible_to(Current.user)
                  .includes(:contract, :alert_recipients)
                  .order(trigger_date: :asc)

    alerts = alerts.where(status: params[:status]) if params[:status].present?

    @overdue_alerts = alerts.overdue.to_a
    @today_alerts = alerts.due_today.to_a
    @upcoming_alerts = alerts.upcoming.limit(20).to_a
    @scheduled_alerts = alerts.scheduled.limit(20).to_a
    @acknowledged_alerts_count = AlertRecipient.where(user_id: Current.user.id)
                                              .where.not(read_at: nil)
                                              .count
  end

  def acknowledge
    @alert.acknowledge!(user: Current.user)
    log_audit("alert_acknowledged", contract: @alert.contract, details: "Acknowledged #{@alert.alert_type_label} alert for #{@alert.contract&.title}")

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove(dom_id(@alert))
      end
      format.html { redirect_to alerts_path, notice: "Alert acknowledged." }
    end
  end

  def snooze
    days = (params[:days] || 7).to_i.clamp(1, 90)
    @alert.snooze!(user: Current.user, days: days)
    log_audit("alert_snoozed", contract: @alert.contract, details: "Snoozed #{@alert.alert_type_label} alert for #{@alert.contract&.title} for #{days} days")

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove(dom_id(@alert))
      end
      format.html { redirect_to alerts_path, notice: "Alert snoozed for #{days} days." }
    end
  end

  private

  def set_alert
    @alert = Alert.for_user(Current.user).find(params[:id])
  end
end
