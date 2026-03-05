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

    @alert_preference = AlertPreference.for(Current.user, Current.organization)
    @selected_bucket = params[:bucket].presence_in(BUCKETS) || "active"
    alerts_by_bucket = partition_alerts_by_bucket(alerts.to_a, @alert_preference)
    @bucket_counts = alerts_by_bucket.transform_values(&:size)
    @filtered_alerts = alerts_by_bucket.fetch(@selected_bucket, [])
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

  def partition_alerts_by_bucket(alerts, alert_preference)
    {
      "active" => alerts.select { |alert| alert.active_for_preference?(alert_preference) },
      "overdue" => alerts.select { |alert| alert.overdue_for_preference?(alert_preference) },
      "today" => alerts.select { |alert| alert.due_today_for_preference?(alert_preference) },
      "upcoming" => alerts.select { |alert| alert.trigger_date > Date.current && alert.trigger_date <= Date.current + Alert::UPCOMING_HORIZON_DAYS },
      "scheduled" => alerts.select { |alert| alert.trigger_date > Date.current + Alert::UPCOMING_HORIZON_DAYS }
    }
  end

  def set_alert
    @alert = Alert.for_user(Current.user).find(params[:id])
  end
end
