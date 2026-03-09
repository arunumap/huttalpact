class LeaseOptionsController < ApplicationController
  include ReviewGuard

  before_action :set_contract
  before_action :set_lease_option, only: %i[edit update destroy]
  before_action :block_if_in_review

  def new
    @lease_option = @contract.lease_options.build
  end

  def create
    @lease_option = @contract.lease_options.build(lease_option_params)
    if @lease_option.save
      GenerateContractAlertsJob.perform_later(@contract.id)
      log_audit("updated", contract: @contract, details: "Added #{@lease_option.option_type} option")
      redirect_to @contract, notice: "Lease option added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @lease_option.update(lease_option_params)
      GenerateContractAlertsJob.perform_later(@contract.id)
      log_audit("updated", contract: @contract, details: "Updated #{@lease_option.option_type} option")
      redirect_to @contract, notice: "Lease option updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @lease_option.destroy!
    GenerateContractAlertsJob.perform_later(@contract.id)
    log_audit("updated", contract: @contract, details: "Removed lease option")
    redirect_to @contract, notice: "Lease option removed.", status: :see_other
  end

  private

  def set_contract
    @contract = Contract.find(params[:contract_id])
  end

  def set_lease_option
    @lease_option = @contract.lease_options.find(params[:id])
  end

  def lease_option_params
    params.require(:lease_option).permit(
      :option_type, :exercise_deadline, :notice_deadline,
      :term_length_months, :rent_terms, :penalty_amount, :conditions
    )
  end
end
