class ApplicationJob < ActiveJob::Base
  # Retry on transient OpenAI / network blips with exponential backoff.
  retry_on AI::Client::TransientError, wait: :exponentially_longer, attempts: 5
  retry_on AI::Client::RateLimitError, wait: 60.seconds,            attempts: 5
  retry_on Faraday::TimeoutError,      wait: :exponentially_longer, attempts: 3

  # Don't retry validation / auth errors — they won't fix themselves.
  discard_on ActiveRecord::RecordNotFound
  discard_on Github::Client::NotFoundError
  discard_on Github::Client::AuthError
end
