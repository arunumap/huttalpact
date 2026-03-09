class LeaseDetailsController < ApplicationController
  include ReviewGuard

  before_action :set_contract
  before_action :set_lease_detail
  before_action :block_if_in_review, only: %i[edit update]

  def edit
  end

  def update
    if @lease_detail.update(lease_detail_params)
      log_audit("updated", contract: @contract, details: "Updated lease details")
      redirect_to @contract, notice: "Lease details updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_contract
    @contract = Contract.find(params[:contract_id])
  end

  def set_lease_detail
    @lease_detail = @contract.lease_detail || @contract.build_lease_detail
  end

  def lease_detail_params
    params.require(:lease_detail).permit(
      :lease_type, :rentable_sqft, :usable_sqft, :load_factor, :permitted_use,
      :security_deposit, :security_deposit_conditions, :parking_spaces, :parking_monthly_cost,
      :free_rent_months, :rent_commencement_date,
      :percentage_rent_breakpoint, :percentage_rent_rate, :percentage_rent_report_date,
      :cam_base_amount, :cam_base_year, :cam_cap_percentage, :cam_cap_type,
      :cam_reconciliation_month, :cam_audit_rights, :cam_gross_up_provision, :cam_controllable_cap,
      :ti_allowance_psf, :ti_total_amount, :ti_deadline, :ti_disbursement_type,
      :ti_amortization_rate, :ti_amortization_term_months,
      :ti_landlord_work_description, :ti_tenant_work_description
    )
  end
end
