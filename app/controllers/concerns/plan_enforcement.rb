module PlanEnforcement
  extend ActiveSupport::Concern

  private

  def enforce_contract_limit!
    return unless current_organization&.at_contract_limit?

    redirect_to contracts_path,
      alert: "You've reached the #{current_organization.plan_display_name} plan limit of #{current_organization.plan_contract_limit} contracts. <a href='#{pricing_path}' class='underline font-semibold'>Upgrade your plan</a> to add more."
  end

  def enforce_extraction_limit!
    current_organization&.reset_monthly_extractions_if_needed!
    return unless current_organization&.at_extraction_limit?

    redirect_to @contract || contracts_path,
      alert: "You've used all #{current_organization.plan_extraction_limit} AI extractions for this month. <a href='#{pricing_path}' class='underline font-semibold'>Upgrade your plan</a> for more."
  end
end
