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

    # Upcoming renewals (next 90 days, grouped for 30/60/90 display)
    @upcoming_renewals = Contract.not_archived.where.not(next_renewal_date: nil)
                               .where(next_renewal_date: Date.current..90.days.from_now)
                               .order(:next_renewal_date)
    @renewals_30 = @upcoming_renewals.select { |c| c.next_renewal_date <= 30.days.from_now.to_date }
    @renewals_60 = @upcoming_renewals.select { |c| c.next_renewal_date <= 60.days.from_now.to_date }
    @renewals_90 = @upcoming_renewals

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
  end
end
