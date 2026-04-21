module AI
  # Thin wrapper around the ruby-openai client. Centralizes:
  #   - model selection (reads from Rails.application.config.ai_models)
  #   - retry-on-transient-error behavior
  #   - token accounting via tiktoken_ruby
  #   - structured logging
  #
  # All AI services in this app go through this class so that swapping models,
  # adding caching, or wiring a different provider later touches exactly one file.
  class Client
    class Error < StandardError; end
    class RateLimitError < Error; end
    class TransientError < Error; end

    MAX_RETRIES    = 3
    RETRY_BASE_SEC = 0.75

    def initialize(client: OpenAI::Client.new)
      @client = client
    end

    # Sends a chat completion. Accepts an array of {role:, content:} hashes.
    # Returns the assistant's text content as a String.
    def chat(messages:, model: nil, temperature: 0.2, max_tokens: 1_500, response_format: nil)
      model ||= Rails.application.config.ai_models.chat
      params = {
        model: model,
        messages: messages,
        temperature: temperature,
        max_tokens: max_tokens
      }
      params[:response_format] = response_format if response_format

      response = with_retry { @client.chat(parameters: params) }
      extract_content(response)
    end

    # Generates an embedding vector for a single string, or a batch of strings.
    # Returns a Float Array (single) or Array<Array<Float>> (batch).
    def embed(input, model: nil)
      model ||= Rails.application.config.ai_models.embedding
      payload = { model: model, input: input }
      response = with_retry { @client.embeddings(parameters: payload) }

      vectors = response.dig("data")&.map { |d| d["embedding"] } || []
      input.is_a?(Array) ? vectors : vectors.first
    end

    # Counts tokens for a given string against a target model.
    # Falls back to a 4-chars-per-token heuristic if tiktoken can't load the encoding.
    def self.token_count(text, model: nil)
      model ||= Rails.application.config.ai_models.chat
      encoder = Tiktoken.encoding_for_model(model) rescue Tiktoken.get_encoding("cl100k_base")
      encoder.encode(text.to_s).length
    rescue StandardError
      (text.to_s.length / 4.0).ceil
    end

    private

    def extract_content(response)
      choice = response.dig("choices", 0, "message", "content")
      raise Error, "Empty OpenAI response: #{response.inspect}" if choice.blank?

      choice
    end

    def with_retry
      attempts = 0
      begin
        attempts += 1
        yield
      rescue Faraday::TooManyRequestsError, OpenAI::Error => e
        raise RateLimitError, e.message if e.message.to_s.match?(/rate limit/i) && attempts >= MAX_RETRIES
        raise TransientError, e.message if attempts >= MAX_RETRIES

        sleep(RETRY_BASE_SEC * (2**(attempts - 1)))
        retry
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
        raise TransientError, e.message if attempts >= MAX_RETRIES

        sleep(RETRY_BASE_SEC * (2**(attempts - 1)))
        retry
      end
    end
  end
end
