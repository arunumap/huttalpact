class AlertsController < ApplicationController
  include Pagy::Backend
  include ActionView::RecordIdentifier

  BUCKETS = %w[active overdue today upcoming scheduled].freeze

  before_action :set_alert, only: %i[acknowledge snooze]

  def index
    alerts = Alert.visible_to(Current.user)
                  .includes(:contract, :alert_recipients)
                  .order(trigger_date: :asc)

    alerts = alerts.where(status: params[:status]) if params[:status].present?

    @selected_bucket = params[:bucket].presence_in(BUCKETS) || "active"
    @bucket_counts = bucket_counts(alerts)
    @filtered_alerts = alerts_for_bucket(alerts, @selected_bucket).to_a
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

  def bucket_counts(alerts)
    {
      "active" => alerts.where(trigger_date: ..Date.current).count,
      "overdue" => alerts.where(status: "pending", trigger_date: ..Date.yesterday).count,
      "today" => alerts.where(trigger_date: Date.current).count,
      "upcoming" => alerts.upcoming.count,
      "scheduled" => alerts.scheduled.count
    }
  end

  def alerts_for_bucket(alerts, bucket)
    case bucket
    when "overdue"
      alerts.where(status: "pending", trigger_date: ..Date.yesterday)
    when "today"
      alerts.where(trigger_date: Date.current)
    when "upcoming"
      alerts.upcoming
    when "scheduled"
      alerts.scheduled
    else
      alerts.where(trigger_date: ..Date.current)
    end
  end

  def set_alert
    @alert = Alert.for_user(Current.user).find(params[:id])
  end
end
