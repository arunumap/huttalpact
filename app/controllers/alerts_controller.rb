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
    @contract_filter_options = Current.organization.contracts
                                               .where.not(uploaded_by_id: nil)
                                               .order(:title)
                                               .pluck(:title, :id)
    @selected_buckets = selected_buckets
    @selected_contract_ids = selected_contract_ids
    alerts = apply_contract_filter(alerts)
    alerts_by_bucket = partition_alerts_by_bucket(alerts.to_a, @alert_preference)
    @bucket_counts = alerts_by_bucket.transform_values(&:size)
    @filtered_alerts = @selected_buckets.flat_map { |bucket| alerts_by_bucket.fetch(bucket, []) }
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

  def selected_buckets
    selected = Array(params[:buckets]).filter_map { |bucket| bucket.presence_in(BUCKETS) }
    return selected if selected.present?
    return BUCKETS if params[:buckets_filter_present].present?

    [ "active" ]
  end

  def selected_contract_ids
    valid_contract_ids = Current.organization.contracts.where.not(uploaded_by_id: nil).pluck(:id).map(&:to_s)
    Array(params[:contract_ids]).reject(&:blank?).select { |contract_id| valid_contract_ids.include?(contract_id) }
  end

  def apply_contract_filter(alerts)
    return alerts if @selected_contract_ids.empty?

    alerts.joins(:contract).where(contracts: { id: @selected_contract_ids })
  end

  def set_alert
    @alert = Alert.for_user(Current.user).find(params[:id])
  end
end
