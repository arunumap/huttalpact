class OnboardingController < ApplicationController
  layout "onboarding"

  before_action :require_authentication
  before_action :set_organization
  before_action :ensure_onboarding_required
  before_action :set_progress

  def organization
    redirect_to onboarding_contract_path if @organization.onboarding_step_index > 0
  end

  def update_organization
    if @organization.update(organization_params)
      @organization.advance_onboarding!("contract")
      redirect_to onboarding_contract_path
    else
      render :organization, status: :unprocessable_entity
    end
  end

  def contract
    if @organization.onboarding_step_index < 1
      redirect_to onboarding_organization_path
      return
    end

    redirect_to onboarding_invite_path if @organization.onboarding_step_index > 1
  end

  def create_contract
    uploaded_files = Array(params[:contract_documents]).compact_blank

    if uploaded_files.empty?
      flash.now[:alert] = "Please upload at least one document or skip this step."
      render :contract, status: :unprocessable_entity
      return
    end

    contract = ContractDraftCreatorService.new(
      user: Current.user,
      organization: @organization,
      files: uploaded_files
    ).call

    log_audit("created", contract: contract, details: "Created draft contract during onboarding")
    @organization.advance_onboarding!("invite")
    redirect_to onboarding_invite_path, notice: "Draft contract created. AI extraction is running now."
  rescue ArgumentError, ActiveRecord::RecordInvalid
    flash.now[:alert] = "Could not create a draft contract. Please try again."
    render :contract, status: :unprocessable_entity
  end

  def skip_contract
    @organization.advance_onboarding!("invite")
    redirect_to onboarding_invite_path
  end

  def invite
    if @organization.onboarding_step_index < 2
      redirect_to onboarding_contract_path
      return
    end
    @invitation = Invitation.new
    @pending_invitations = @organization.invitations.pending.order(created_at: :desc)
  end

  def create_invite
    @invitation = @organization.invitations.new(invitation_params.merge(inviter: Current.user))

    if @invitation.save
      InvitationMailer.invite(@invitation).deliver_later
      redirect_to onboarding_invite_path, notice: "Invitation sent to #{@invitation.email}."
    else
      @pending_invitations = @organization.invitations.pending.order(created_at: :desc)
      render :invite, status: :unprocessable_entity
    end
  end

  def complete
    @organization.complete_onboarding!
    redirect_to root_path, notice: "You're all set!"
  end

  private

  def organization_params
    params.require(:organization).permit(:name)
  end

  def invitation_params
    permitted = params.require(:invitation).permit(:email)
    role = params[:invitation][:role]
    permitted[:role] = Membership::ROLES.excluding(Membership::OWNER_ROLE).include?(role) ? role : "member"
    permitted
  end

  def ensure_onboarding_required
    return unless @organization
    return unless Current.user
    return unless @organization.onboarding_complete?

    redirect_to root_path
  end

  def set_organization
    @organization = Current.organization || Current.user&.organizations&.first
    if @organization.present?
      Current.organization ||= @organization
      set_current_tenant(@organization)
      return
    end

    redirect_to new_registration_path, alert: "Please create an organization to continue."
  end

  def set_progress
    @onboarding_steps = Organization::ONBOARDING_STEPS
    @onboarding_step_index = @organization&.onboarding_step_index.to_i
  end
end
