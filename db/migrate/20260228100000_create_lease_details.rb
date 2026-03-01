class CreateLeaseDetails < ActiveRecord::Migration[8.1]
  def change
    create_table :lease_details, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :contract, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }

      # Lease classification
      t.string :lease_type # gross, modified_gross, nnn, percentage

      # Space metrics
      t.decimal :rentable_sqft, precision: 10, scale: 2
      t.decimal :usable_sqft, precision: 10, scale: 2
      t.decimal :load_factor, precision: 5, scale: 4
      t.string :permitted_use

      # Security deposit
      t.decimal :security_deposit, precision: 12, scale: 2
      t.text :security_deposit_conditions

      # Parking
      t.integer :parking_spaces
      t.decimal :parking_monthly_cost, precision: 10, scale: 2

      # Free rent
      t.integer :free_rent_months
      t.date :rent_commencement_date

      # Percentage rent
      t.decimal :percentage_rent_breakpoint, precision: 12, scale: 2
      t.decimal :percentage_rent_rate, precision: 5, scale: 2
      t.date :percentage_rent_report_date

      # CAM / Operating expenses
      t.decimal :cam_base_amount, precision: 12, scale: 2
      t.integer :cam_base_year
      t.decimal :cam_cap_percentage, precision: 5, scale: 2
      t.string :cam_cap_type # cumulative, non_cumulative, none
      t.integer :cam_reconciliation_month # 1-12
      t.boolean :cam_audit_rights, default: false
      t.boolean :cam_gross_up_provision, default: false
      t.decimal :cam_controllable_cap, precision: 5, scale: 2

      # Tenant improvements
      t.decimal :ti_allowance_psf, precision: 10, scale: 2
      t.decimal :ti_total_amount, precision: 12, scale: 2
      t.date :ti_deadline
      t.string :ti_disbursement_type # lump_sum, draw_schedule, reimbursement
      t.decimal :ti_amortization_rate, precision: 5, scale: 2
      t.integer :ti_amortization_term_months
      t.text :ti_landlord_work_description
      t.text :ti_tenant_work_description

      t.timestamps
    end
  end
end
