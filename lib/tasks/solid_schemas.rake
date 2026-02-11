namespace :solid do
  desc "Load Solid Queue, Cache, and Cable schemas if their tables don't exist (for single-database deployments like Heroku)"
  task ensure_schemas: :environment do
    conn = ActiveRecord::Base.connection

    schemas = {
      "solid_queue_jobs" => "db/queue_schema.rb",
      "solid_cache_entries" => "db/cache_schema.rb",
      "solid_cable_messages" => "db/cable_schema.rb"
    }

    schemas.each do |table, schema_file|
      if conn.table_exists?(table)
        puts "  #{table} exists — skipping #{schema_file}"
      else
        puts "  Loading #{schema_file}..."
        load Rails.root.join(schema_file)
      end
    end
  end
end
