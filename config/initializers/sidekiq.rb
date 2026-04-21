require "sidekiq"
require "sidekiq/cron/job"

redis_config = {
  url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
  network_timeout: 5
}

Sidekiq.configure_server do |config|
  config.redis = redis_config

  # Load scheduled jobs from config/sidekiq_cron.yml on boot
  config.on(:startup) do
    schedule_file = Rails.root.join("config/sidekiq_cron.yml")
    if schedule_file.exist?
      schedule = YAML.load_file(schedule_file)
      Sidekiq::Cron::Job.load_from_hash(schedule)
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = redis_config
end
