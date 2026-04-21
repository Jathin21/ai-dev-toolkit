require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"

abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"
require "webmock/rspec"
require "vcr"
require "factory_bot_rails"
require "shoulda/matchers"

Dir[Rails.root.join("spec/support/**/*.rb")].each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

# Block all real HTTP except localhost (for Capybara). OpenAI + GitHub are stubbed via VCR.
WebMock.disable_net_connect!(allow_localhost: true)

VCR.configure do |c|
  c.cassette_library_dir         = "spec/vcr_cassettes"
  c.hook_into :webmock
  c.configure_rspec_metadata!
  c.filter_sensitive_data("<OPENAI_API_KEY>") { ENV["OPENAI_API_KEY"] }
  c.filter_sensitive_data("<GITHUB_TOKEN>")   { ENV["GITHUB_TOKEN"]   }
  c.default_cassette_options = { record: ENV.fetch("VCR_RECORD_MODE", "none").to_sym }
end

RSpec.configure do |config|
  config.fixture_paths = [Rails.root.join("spec/fixtures").to_s]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods
  config.include Devise::Test::ControllerHelpers,    type: :controller
  config.include Devise::Test::IntegrationHelpers,   type: :request
end

Shoulda::Matchers.configure do |c|
  c.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
