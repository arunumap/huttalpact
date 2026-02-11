class RegistrationsController < ApplicationController
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
      flash.now[:alert] = "Invitation link is invalid or expired."
      render :new, status: :unprocessable_entity
      return
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

    start_new_session_for @user
    destination = if @invitation&.organization&.onboarding_complete?
      root_path
    else
      onboarding_organization_path
    end
    redirect_to destination, notice: "Welcome to HuttalPact!"
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  private

  def user_params
    params.require(:user).permit(:email_address, :password, :password_confirmation, :first_name, :last_name)
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
end
