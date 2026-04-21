source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.3.0"

# Core Rails
gem "rails", "~> 7.1.3"
gem "pg", "~> 1.5"
gem "puma", "~> 6.4"

# Frontend - Hotwire stack
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "tailwindcss-rails"

# Views / helpers
gem "jbuilder"
gem "view_component"

# Background jobs
gem "sidekiq", "~> 7.2"
gem "redis", "~> 5.0"
gem "sidekiq-cron"

# AI / LLM integrations
gem "ruby-openai", "~> 7.0"        # OpenAI API client
gem "tiktoken_ruby"                 # Token counting for prompts

# pgvector for embeddings-based search
gem "neighbor", "~> 0.4"            # ActiveRecord adapter for pgvector

# GitHub integration
gem "octokit", "~> 8.0"             # GitHub REST API
gem "faraday-retry"

# Authentication / authorization
gem "devise", "~> 4.9"
gem "pundit", "~> 2.3"

# Rate limiting / security
gem "rack-attack"
gem "bootsnap", require: false

# Platform-specific
gem "tzinfo-data", platforms: %i[windows jruby]

group :development, :test do
  gem "debug", platforms: %i[mri windows]
  gem "rspec-rails", "~> 6.1"
  gem "factory_bot_rails"
  gem "faker"
  gem "webmock"
  gem "vcr"
  gem "dotenv-rails"
  gem "rubocop-rails", require: false
  gem "brakeman", require: false
end

group :development do
  gem "web-console"
  gem "letter_opener"
  gem "foreman"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
  gem "shoulda-matchers"
  gem "simplecov", require: false
end
