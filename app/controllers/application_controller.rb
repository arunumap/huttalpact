class ApplicationController < ActionController::Base
  include Authentication
  include Pagy::Backend
  include Auditable
  include PlanEnforcement

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
  rescue_from ActionController::ParameterMissing, with: :bad_request

  set_current_tenant_through_filter
  before_action :set_tenant
  before_action :set_sentry_context
  before_action :set_unread_alert_count
  before_action :redirect_to_onboarding

  helper_method :current_organization

  private

  def current_organization
    Current.organization
  end

  def set_tenant
    return unless Current.user

    organization = Current.user.organizations.first

    if organization.nil?
      redirect_to new_registration_path, alert: "Please create an organization to continue."
      return
    end

    Current.organization = organization
    set_current_tenant(organization)
  end

  def set_unread_alert_count
    return unless Current.user
    return unless Current.organization

    @unread_alert_count = AlertRecipient
      .joins(alert: :organization)
      .where(user_id: Current.user.id, alerts: { organization_id: Current.organization.id })
      .where(alerts: { trigger_date: ..(Date.current + Alert::UPCOMING_HORIZON_DAYS) })
      .where(alerts: { status: %w[pending sent] })
      .unread
      .not_snoozed
      .count
    @recent_alerts = Alert
      .where(organization_id: Current.organization.id)
      .visible_to(Current.user)
      .actionable
      .includes(:contract)
      .order(trigger_date: :asc)
      .limit(5)
  end

  def redirect_to_onboarding
    return unless Current.user
    return unless Current.organization
    return if Current.organization.onboarding_complete?
    return if controller_name == "onboarding"
    return if controller_name.in?(%w[sessions registrations passwords pricing])

    case Current.organization.onboarding_step_index
    when 0
      redirect_to onboarding_organization_path
    when 1
      redirect_to onboarding_contract_path
    else
      redirect_to onboarding_invite_path
    end
  end

  def set_sentry_context
    return unless Sentry.initialized?
    return unless Current.user

    Sentry.set_user(id: Current.user.id, email: Current.user.email_address)
    Sentry.set_tags(
      organization_id: Current.organization&.id,
      plan: Current.organization&.plan
    )
  end

  def record_not_found
    respond_to do |format|
      format.html { redirect_back fallback_location: root_path, alert: "The record you were looking for could not be found." }
      format.turbo_stream { head :not_found }
    end
  end

  def bad_request(exception)
    respond_to do |format|
      format.html { redirect_back fallback_location: root_path, alert: "Invalid request: #{exception.message}" }
      format.turbo_stream { head :bad_request }
    end
  end
end
