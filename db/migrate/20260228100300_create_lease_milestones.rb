class CreateLeaseMilestones < ActiveRecord::Migration[8.1]
  def change
    create_table :lease_milestones, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :contract, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :organization, type: :uuid, null: false, foreign_key: true

      t.string :milestone_type, null: false # cam_reconciliation, insurance_renewal, estoppel_response, ti_completion, percentage_rent_report, guarantee_burnoff, custom
      t.date :due_date, null: false
      t.text :description
      t.boolean :recurring, default: false
      t.string :recurrence_interval # monthly, quarterly, annual

      t.timestamps

      t.index [ :contract_id, :milestone_type ]
      t.index [ :organization_id, :due_date ]
    end
  end
end
