require_relative "boot"

require "rails/all"

Bundler.require(*Rails.groups)

module AiDevToolkit
  class Application < Rails::Application
    config.load_defaults 7.1

    config.autoload_lib(ignore: %w[assets tasks])

    config.time_zone = "UTC"
    config.active_record.default_timezone = :utc

    # Use Sidekiq for all background jobs
    config.active_job.queue_adapter = :sidekiq

    # Autoload services and their sub-namespaces
    config.autoload_paths += %W[
      #{config.root}/app/services
      #{config.root}/app/services/ai
      #{config.root}/app/services/embeddings
      #{config.root}/app/services/github
      #{config.root}/app/services/database_query
    ]

    # Strict API defaults for the /api/v1 namespace, but keep HTML views
    config.generators do |g|
      g.test_framework :rspec, fixtures: true
      g.fixture_replacement :factory_bot, dir: "spec/factories"
      g.view_specs false
      g.helper_specs false
    end
  end
end
