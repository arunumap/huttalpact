class DashboardController < ApplicationController
  def show
    # Summary stats (exclude archived)
    @total_contracts = Contract.not_archived.count
    @active_contracts = Contract.active.count
    @expiring_soon_contracts = Contract.expiring_soon.count
    @expired_contracts = Contract.expired.count

    # Revenue vs Spend (already scoped to active)
    @total_monthly_spend = Contract.active.outbound.sum(:monthly_value) || 0
    @total_monthly_revenue = Contract.active.inbound.sum(:monthly_value) || 0
    @total_monthly_value = Contract.active.sum(:monthly_value) || 0
    @total_annual_value = Contract.active.where.not(total_value: nil).sum(:total_value) || 0

    # Upcoming renewals — use SQL date filtering, not Ruby .select
    renewals_base = Contract.not_archived.where.not(next_renewal_date: nil)
                           .where(next_renewal_date: Date.current..90.days.from_now.to_date)
                           .order(:next_renewal_date)
    @renewals_30 = renewals_base.where(next_renewal_date: ..30.days.from_now.to_date)
    @renewals_60 = renewals_base.where(next_renewal_date: ..60.days.from_now.to_date)
    @renewals_90 = renewals_base
    @upcoming_renewals = renewals_base

    # Expiring contracts (end_date within 90 days, not already expired/archived)
    @expiring_contracts = Contract.where.not(end_date: nil)
                                 .where(end_date: Date.current..90.days.from_now)
                                 .where.not(status: %w[expired archived])
                                 .order(:end_date)
                                 .limit(10)

    # Status distribution (exclude archived)
    @status_counts = Contract.not_archived.group(:status).count
    @status_counts.default = 0

    # Revenue by contract type (inbound)
    @revenue_by_type = Contract.active.inbound
                               .where.not(contract_type: [ nil, "" ])
                               .group(:contract_type)
                               .sum(:monthly_value)
                               .sort_by { |_, v| -v.to_f }

    # Spend by contract type (outbound)
    @spend_by_type = Contract.active.outbound
                             .where.not(contract_type: [ nil, "" ])
                             .group(:contract_type)
                             .sum(:monthly_value)
                             .sort_by { |_, v| -v.to_f }

    # Value by vendor (top 5)
    @value_by_vendor = Contract.active
                               .where.not(vendor_name: [ nil, "" ])
                               .group(:vendor_name)
                               .sum(:monthly_value)
                               .sort_by { |_, v| -v.to_f }
                               .first(5)

    # Recently added
    @recent_contracts = Contract.order(created_at: :desc).limit(5)

    # Extraction usage and billing transparency
    set_extraction_dashboard_summary

    # Lease insights — only load when lease contracts exist
    @lease_contract_count = Contract.not_archived.where(contract_type: "lease").count
    if @lease_contract_count > 0
      # Upcoming option deadlines (exercise or notice deadline within 90 days)
      @upcoming_option_deadlines = LeaseOption
        .joins(:contract)
        .merge(Contract.not_archived.where(contract_type: "lease"))
        .where("lease_options.exercise_deadline >= ? OR lease_options.notice_deadline >= ?", Date.current, Date.current)
        .where("lease_options.exercise_deadline <= ? OR lease_options.notice_deadline <= ?", 90.days.from_now.to_date, 90.days.from_now.to_date)
        .order(Arel.sql("COALESCE(lease_options.notice_deadline, lease_options.exercise_deadline) ASC"))
        .limit(5)

      # Upcoming rent escalations (next 12 months)
      @upcoming_escalations = RentEscalation
        .joins(:contract)
        .merge(Contract.not_archived.where(contract_type: "lease"))
        .where(effective_date: Date.current..12.months.from_now.to_date)
        .order(effective_date: :asc)
        .limit(5)

      # TI deadlines approaching (within 6 months)
      @upcoming_ti_deadlines = LeaseDetail
        .joins(:contract)
        .merge(Contract.not_archived.where(contract_type: "lease"))
        .where.not(ti_deadline: nil)
        .where(ti_deadline: Date.current..6.months.from_now.to_date)
        .order(ti_deadline: :asc)
        .limit(5)

      # Upcoming milestones (next 90 days)
      @upcoming_milestones = LeaseMilestone
        .joins(:contract)
        .merge(Contract.not_archived.where(contract_type: "lease"))
        .where(due_date: Date.current..90.days.from_now.to_date)
        .order(due_date: :asc)
        .limit(5)
    end
  end

  private

  def set_extraction_dashboard_summary
    org = current_organization
    return unless org

    limit = org.plan_extraction_limit
    @dashboard_extraction_limit_display = limit == Float::INFINITY ? "∞" : limit
    @dashboard_extraction_usage_percent = if limit == Float::INFINITY || limit.to_i <= 0
      0
    else
      ((org.ai_extractions_count.to_f / limit) * 100).round
    end

    @dashboard_overage_rate_cents = org.plan_extraction_overage_cents
    @dashboard_estimated_bill_cents = estimated_dashboard_bill_cents_for(org)
    @dashboard_upgrade_overage_nudge = dashboard_upgrade_overage_nudge_for(org)
  end

  def estimated_dashboard_bill_cents_for(org)
    estimated_base_subscription_cents_for(org) + org.estimated_extraction_overage_cents
  end

  def estimated_base_subscription_cents_for(org)
    tier = PlanCatalogService.tier_for(org.plan)
    return 0 unless tier

    inferred_subscription_interval(org.active_subscription) == :annual ? tier.annual_price_cents.to_i : tier.monthly_price_cents.to_i
  end

  def inferred_subscription_interval(subscription)
    return :monthly unless subscription&.current_period_start && subscription&.current_period_end

    period_days = (subscription.current_period_end.to_date - subscription.current_period_start.to_date).to_i
    period_days > 45 ? :annual : :monthly
  end

  def dashboard_upgrade_overage_nudge_for(org)
    limit = org.plan_extraction_limit
    return nil if limit == Float::INFINITY
    return nil unless @dashboard_extraction_usage_percent >= 80

    current_tier = PlanCatalogService.tier_for(org.plan)
    return nil unless current_tier

    current_rate_cents = current_tier.extraction_overage_cents.to_i
    return nil unless current_rate_cents.positive?

    cheaper_tier, cheaper_rate_cents = PlanCatalogService.active_tiers_for_billing
      .select { |tier| tier.rank.to_i > current_tier.rank.to_i }
      .map { |tier| [ tier, candidate_overage_rate_cents(tier) ] }
      .select { |_, rate| rate.present? && rate < current_rate_cents }
      .min_by { |_, rate| rate }

    return nil unless cheaper_tier && cheaper_rate_cents

    savings_percent = ((current_rate_cents - cheaper_rate_cents) * 100.0 / current_rate_cents).round
    return nil if savings_percent <= 0

    { tier_name: cheaper_tier.name, savings_percent: savings_percent }
  end

  def candidate_overage_rate_cents(tier)
    rate = tier.extraction_overage_cents.to_i
    return nil unless rate.positive?
    return nil if tier.extraction_limit.nil?

    rate
  end
end
