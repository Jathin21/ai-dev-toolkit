class Rack::Attack
  # Throttle AI-heavy endpoints — these hit the OpenAI API and must be protected.
  throttle("ai_requests/ip", limit: 30, period: 1.minute) do |req|
    req.ip if req.path.match?(%r{/(code_searches|queries|pull_requests/\d+/summarize)})
  end

  # General per-IP limiter
  throttle("req/ip", limit: 300, period: 5.minutes) do |req|
    req.ip unless req.path.start_with?("/assets", "/up")
  end

  self.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"]
    now = match_data[:epoch_time]
    headers = {
      "Content-Type" => "application/json",
      "RateLimit-Limit" => match_data[:limit].to_s,
      "RateLimit-Remaining" => "0",
      "RateLimit-Reset" => (now + (match_data[:period] - (now % match_data[:period]))).to_s
    }
    [429, headers, [{ error: "Rate limit exceeded. Please retry shortly." }.to_json]]
  end
end

Rails.application.config.middleware.use Rack::Attack
