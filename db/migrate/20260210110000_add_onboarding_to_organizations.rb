class AddOnboardingToOrganizations < ActiveRecord::Migration[8.1]
  def up
    add_column :organizations, :onboarding_step, :integer, null: false, default: 0
    add_column :organizations, :onboarding_completed_at, :datetime

    execute <<~SQL
      UPDATE organizations
      SET onboarding_step = 2,
          onboarding_completed_at = NOW()
    SQL
  end

  def down
    remove_column :organizations, :onboarding_completed_at
    remove_column :organizations, :onboarding_step
  end
end
