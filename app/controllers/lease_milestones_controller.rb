class LeaseMilestonesController < ApplicationController
  include ReviewGuard

  before_action :set_contract
  before_action :set_lease_milestone, only: %i[edit update destroy]
  before_action :block_if_in_review

  def new
    @lease_milestone = @contract.lease_milestones.build
  end

  def create
    @lease_milestone = @contract.lease_milestones.build(lease_milestone_params)
    @lease_milestone.organization = @contract.organization
    if @lease_milestone.save
      GenerateContractAlertsJob.perform_later(@contract.id)
      SyncContractCalendarEventsJob.perform_later(@contract.id)
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
      GenerateContractAlertsJob.perform_later(@contract.id)
      SyncContractCalendarEventsJob.perform_later(@contract.id)
      log_audit("updated", contract: @contract, details: "Updated #{@lease_milestone.milestone_type} milestone")
      redirect_to @contract, notice: "Lease milestone updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @lease_milestone.destroy!
    GenerateContractAlertsJob.perform_later(@contract.id)
    SyncContractCalendarEventsJob.perform_later(@contract.id)
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
end
