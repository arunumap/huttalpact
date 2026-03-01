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
end
