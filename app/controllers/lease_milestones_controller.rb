class LeaseMilestonesController < ApplicationController
  before_action :set_contract
  before_action :set_lease_milestone, only: %i[edit update destroy]

  def new
    @lease_milestone = @contract.lease_milestones.build
  end

  def create
    @lease_milestone = @contract.lease_milestones.build(lease_milestone_params)
    @lease_milestone.organization = @contract.organization
    if @lease_milestone.save
      enqueue_alert_regeneration
      log_audit("updated", contract: @contract, details: "Added #{@lease_milestone.milestone_type} milestone")
      redirect_to @contract, notice: "Lease milestone added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @lease_milestone.update(lease_milestone_params)
      enqueue_alert_regeneration
      log_audit("updated", contract: @contract, details: "Updated #{@lease_milestone.milestone_type} milestone")
      redirect_to @contract, notice: "Lease milestone updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @lease_milestone.destroy!
    enqueue_alert_regeneration
    log_audit("updated", contract: @contract, details: "Removed lease milestone")
    redirect_to @contract, notice: "Lease milestone removed.", status: :see_other
  end

  private

  def set_contract
    @contract = Contract.find(params[:contract_id])
  end

  def set_lease_milestone
    @lease_milestone = @contract.lease_milestones.find(params[:id])
  end

  def lease_milestone_params
    params.require(:lease_milestone).permit(
      :milestone_type, :due_date, :description, :recurring, :recurrence_interval
    )
  end

  def enqueue_alert_regeneration
    GenerateContractAlertsJob.perform_later(@contract.id) if @contract.alert_generation_enabled?
  end
end
