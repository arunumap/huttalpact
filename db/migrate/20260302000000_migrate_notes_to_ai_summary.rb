# frozen_string_literal: true

# Data migration: For contracts that were AI-extracted before the ai_summary
# column existed, the AI-generated summary was stored in the notes field.
# This migration copies those values to ai_summary so notes can be used
# exclusively for user-authored content.
class MigrateNotesToAiSummary < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE contracts
      SET ai_summary = notes
      WHERE ai_summary IS NULL
        AND notes IS NOT NULL
        AND notes != ''
        AND extraction_status = 'completed'
    SQL
  end

  def down
    # No-op: we can't distinguish which notes were AI-generated vs user-authored
    # after the migration has run, so we don't reverse it.
  end
end
