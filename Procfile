web: bundle exec puma -C config/puma.rb
worker: bundle exec sidekiq -c ${SIDEKIQ_CONCURRENCY:-10} -q ai,3 -q indexing,2 -q default,5
release: bin/rails db:migrate
