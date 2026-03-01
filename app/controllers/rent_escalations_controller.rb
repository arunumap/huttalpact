class RentEscalationsController < ApplicationController
  before_action :set_contract
  before_action :set_rent_escalation, only: %i[edit update destroy]

  def new
    @rent_escalation = @contract.rent_escalations.build
  end

  def create
    @rent_escalation = @contract.rent_escalations.build(rent_escalation_params)
    if @rent_escalation.save
      log_audit("updated", contract: @contract, details: "Added rent escalation for #{@rent_escalation.effective_date}")
      redirect_to @contract, notice: "Rent escalation added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @rent_escalation.update(rent_escalation_params)
      log_audit("updated", contract: @contract, details: "Updated rent escalation for #{@rent_escalation.effective_date}")
      redirect_to @contract, notice: "Rent escalation updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @rent_escalation.destroy!
    log_audit("updated", contract: @contract, details: "Removed rent escalation")
    redirect_to @contract, notice: "Rent escalation removed.", status: :see_other
  end

  private

  def set_contract
    @contract = Contract.find(params[:contract_id])
  end

  def set_rent_escalation
    @rent_escalation = @contract.rent_escalations.find(params[:id])
  end

  def rent_escalation_params
    params.require(:rent_escalation).permit(
      :effective_date, :base_rent_monthly, :base_rent_annual,
      :escalation_type, :escalation_value, :description
    )
  end
end
