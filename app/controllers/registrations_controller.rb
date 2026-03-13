class RegistrationsController < ApplicationController
  AD_ATTRIBUTION_QUERY_KEYS = PagesController::AD_ATTRIBUTION_QUERY_KEYS
  ADS_LANDING_SOURCE = PagesController::ADS_LANDING_SOURCE

  allow_unauthenticated_access
  before_action :redirect_if_authenticated, only: [ :new, :create ]
  rate_limit to: 10, within: 1.minute, only: :create, with: -> { redirect_to new_registration_path, alert: "Too many sign-up attempts. Try again later." }

  layout "auth"

  def new
    @invitation = find_invitation
    if params[:token].present? && @invitation.nil?
      redirect_to new_registration_path, alert: "Invitation link is invalid or expired."
      return
    end
    @user = User.new
    @user.email_address = @invitation.email if @invitation
  end

  def create
    @invitation = find_invitation
    @user = User.new(user_params)

    if params[:token].present? && @invitation.nil?
      return render_registration_error(
        status: :unprocessable_entity,
        alert: "Invitation link is invalid or expired."
      )
    end

    if @invitation
      existing_user = User.find_by(email_address: @invitation.email)

      if existing_user
        existing_user.memberships.find_or_create_by!(organization: @invitation.organization) do |membership|
          membership.role = @invitation.role
        end
        @invitation.accept!
        redirect_to new_session_path, notice: "Account already exists. Please sign in to join your organization."
        return
      end

      @user.email_address = @invitation.email
    end

    @user.terms_accepted_at = Time.current if @user.terms_accepted == "1"
    @user.email_verified_at = Time.current if @invitation

    ActiveRecord::Base.transaction do
      @user.save!
      if @invitation
        @invitation.organization.memberships.create!(user: @user, role: @invitation.role)
        @invitation.accept!
      else
        organization = Organization.create!(name: organization_name)
        organization.memberships.create!(user: @user, role: Membership::OWNER_ROLE)
      end
    end

    if @invitation
      UserMailer.welcome(@user).deliver_later
    else
      UserMailer.email_verification(@user).deliver_later
    end
    start_new_session_for @user
    track_analytics_event("sign_up", method: "email", source: params[:source].presence)
    track_conversion_event_signup
    destination = if @invitation&.organization&.onboarding_complete?
      root_path
    elsif @invitation
      onboarding_organization_path
    else
      email_verification_path
    end
    notice = @invitation ? "Welcome to PactBadger!" : "Account created. Check your email to verify your address."
    redirect_to destination, notice: notice
  rescue ActiveRecord::RecordInvalid
    render_registration_error(status: :unprocessable_entity)
  end

  private

  def user_params
    params.require(:user).permit(:email_address, :password, :password_confirmation, :first_name, :last_name, :terms_accepted)
  end

  def organization_name
    name = params.dig(:user, :organization_name).presence
    name || "#{@user.first_name || @user.email_address.split('@').first}'s Organization"
  end

  def find_invitation
    token = params[:token].presence
    return if token.blank?

    Invitation.pending.find_by(token: token)
  end

  def redirect_if_authenticated
    redirect_to root_path if authenticated?
  end

  def ads_landing_signup?
    params[:source].to_s == ADS_LANDING_SOURCE
  end

  def render_registration_error(status:, alert: nil)
    flash.now[:alert] = alert if alert

    if ads_landing_signup?
      @ads_signup_params = request.parameters.slice(*AD_ATTRIBUTION_QUERY_KEYS).compact
      @ads_signup_params["source"] = ADS_LANDING_SOURCE
      @organization_name = params.dig(:user, :organization_name)
      render "pages/ads_contracts", layout: "marketing_funnel", status: status
    else
      render :new, status: status
    end
  end

  def track_conversion_event_signup
    flash[:ga_conversion_event] = { event: "conversion_event_signup", params: { source: params[:source].presence || "organic" } }.to_json
  end
end
