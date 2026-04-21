require "openai"

OpenAI.configure do |config|
  config.access_token = ENV.fetch("OPENAI_API_KEY", nil)
  config.organization_id = ENV["OPENAI_ORGANIZATION_ID"]
  config.log_errors = Rails.env.development?
  config.request_timeout = 120
end

# Centralized model configuration — change here to upgrade models project-wide.
Rails.application.config.ai_models = ActiveSupport::OrderedOptions.new.tap do |m|
  m.chat              = ENV.fetch("OPENAI_CHAT_MODEL", "gpt-4o-mini")
  m.chat_reasoning    = ENV.fetch("OPENAI_CHAT_REASONING_MODEL", "gpt-4o")
  m.embedding         = ENV.fetch("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small")
  m.embedding_dims    = Integer(ENV.fetch("OPENAI_EMBEDDING_DIMS", 1536))
end
