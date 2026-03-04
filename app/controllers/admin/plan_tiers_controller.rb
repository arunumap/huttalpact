class Admin::PlanTiersController < Admin::BaseController
  before_action :set_plan_tier, only: %i[show edit update destroy activate deactivate sync_to_stripe]

  def index
    @plan_tiers = PlanTier.ordered
  end

  def show
  end

  def new
    @plan_tier = PlanTier.new(
      active: true,
      visible_on_pricing_page: true,
      position: PlanTier.maximum(:position).to_i + 1,
      rank: PlanTier.maximum(:rank).to_i + 1
    )
  end

  def create
    @plan_tier = PlanTier.new(plan_tier_params)
    assign_feature_list

    if @plan_tier.save
      redirect_to admin_plan_tier_path(@plan_tier), notice: "Plan tier created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @plan_tier.assign_attributes(plan_tier_params)
    assign_feature_list

    if @plan_tier.save
      redirect_to admin_plan_tier_path(@plan_tier), notice: "Plan tier updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if protected_tier? || tier_in_use?
      redirect_to admin_plan_tier_path(@plan_tier), alert: destroy_blocker_message
      return
    end

    @plan_tier.destroy!
    redirect_to admin_plan_tiers_path, notice: "Plan tier deleted."
  end

  def activate
    @plan_tier.update!(active: true)
    redirect_to admin_plan_tier_path(@plan_tier), notice: "Plan tier activated."
  end

  def deactivate
    if protected_tier? || tier_in_use?
      redirect_to admin_plan_tier_path(@plan_tier), alert: deactivate_blocker_message
      return
    end

    @plan_tier.update!(active: false)
    redirect_to admin_plan_tier_path(@plan_tier), notice: "Plan tier deactivated."
  end

  def sync_to_stripe
    result = StripeAdminService.sync_plan_tier!(@plan_tier)

    if result[:success]
      message = "Stripe sync complete."
      message += " Created: #{result[:created].join(', ')}." if result[:created].present?
      message += " Skipped: #{result[:skipped].join(', ')}." if result[:skipped].present?
      redirect_to admin_plan_tier_path(@plan_tier), notice: message
    else
      redirect_to admin_plan_tier_path(@plan_tier), alert: "Stripe sync failed: #{result[:message]}"
    end
  end

  private

  def set_plan_tier
    @plan_tier = PlanTier.find(params[:id])
  end

  def plan_tier_params
    params.require(:plan_tier).permit(
      :slug,
      :name,
      :description,
      :rank,
      :position,
      :contract_limit,
      :extraction_limit,
      :user_limit,
      :audit_log_days,
      :monthly_price_cents,
      :annual_price_cents,
      :monthly_lookup_key,
      :annual_lookup_key,
      :active,
      :visible_on_pricing_page,
      :featured,
      :system_tier,
      :default_tier
    )
  end

  def assign_feature_list
    return unless params[:plan_tier].key?(:feature_list_text)

    @plan_tier.feature_list = params[:plan_tier][:feature_list_text]
      .to_s
      .split("\n")
      .map(&:strip)
      .reject(&:blank?)
  end

  def protected_tier?
    @plan_tier.system_tier? || @plan_tier.default_tier?
  end

  def tier_in_use?
    Organization.where(plan: @plan_tier.slug)
                .or(Organization.where(pending_plan: @plan_tier.slug))
                .exists?
  end

  def deactivate_blocker_message
    return "System or default tiers cannot be deactivated." if protected_tier?
    return "This tier is currently used by one or more organizations and cannot be deactivated." if tier_in_use?

    "This tier cannot be deactivated."
  end

  def destroy_blocker_message
    return "System or default tiers cannot be deleted." if protected_tier?
    return "This tier is currently used by one or more organizations and cannot be deleted." if tier_in_use?

    "This tier cannot be deleted."
  end
end
