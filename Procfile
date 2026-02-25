web: MALLOC_ARENA_MAX=2 bundle exec puma -C config/puma.rb
worker: MALLOC_ARENA_MAX=2 bundle exec rake solid_queue:start
release: bin/rails db:prepare solid:ensure_schemas
