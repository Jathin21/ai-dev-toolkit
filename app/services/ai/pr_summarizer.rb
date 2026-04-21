module AI
  # Generates a structured summary + review notes for a single pull request.
  # The prompt asks for JSON so we can store structured fields (risk level,
  # areas-of-concern tags) alongside the human-readable summary.
  class PRSummarizer
    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an expert senior software engineer performing a first-pass review of a pull request.
      You will receive the PR title, description, and unified diff.

      Produce a response as STRICT JSON matching this schema:

      {
        "summary":       "2-4 sentence plain-English description of what this PR changes and why",
        "review_notes":  "bulleted markdown list of the most important things a reviewer should verify or question",
        "risk_level":    "low" | "medium" | "high",
        "areas":         ["short","tag","strings","e.g.","auth","db-migration","api-breaking"],
        "test_coverage": "brief assessment of whether tests are added/modified appropriately"
      }

      Guidelines:
      - Be concrete. Cite file names or function names when relevant.
      - risk_level = "high" for: security-sensitive code, DB migrations, API contract changes,
        auth/permissions logic, cryptography, or anything touching billing/payments.
      - Keep review_notes actionable. "Consider adding a test for the nil case" beats "add more tests".
      - Do NOT invent features the diff doesn't show. If the diff is truncated, say so.
      - Output MUST be valid JSON. No markdown fences, no prose outside the JSON object.
    PROMPT

    def initialize(pull_request, ai_client: AI::Client.new, github_client: nil)
      @pull_request  = pull_request
      @ai_client     = ai_client
      @github_client = github_client || Github::Client.new(
        token: pull_request.repository.user.github_token
      )
    end

    def call
      @pull_request.ai_running!

      diff = @github_client.pull_request_diff(
        @pull_request.repository.full_name,
        @pull_request.number
      )

      content = @ai_client.chat(
        messages: build_messages(diff),
        model:       Rails.application.config.ai_models.chat_reasoning,
        temperature: 0.1,
        max_tokens:  1_800,
        response_format: { type: "json_object" }
      )

      parsed = JSON.parse(content)
      @pull_request.mark_ai_complete!(
        summary:      parsed.fetch("summary"),
        review_notes: parsed.fetch("review_notes"),
        metadata: {
          risk_level:    parsed["risk_level"],
          areas:         parsed["areas"],
          test_coverage: parsed["test_coverage"],
          diff_bytes:    diff.bytesize,
          model:         Rails.application.config.ai_models.chat_reasoning
        }
      )
      @pull_request
    rescue JSON::ParserError, KeyError => e
      @pull_request.mark_ai_failed!("Malformed LLM response: #{e.message}")
      raise
    rescue StandardError => e
      @pull_request.mark_ai_failed!(e)
      raise
    end

    private

    def build_messages(diff)
      user_content = <<~USER
        Pull Request: #{@pull_request.repository.full_name}##{@pull_request.number}
        Title: #{@pull_request.title}

        Description:
        #{@pull_request.body.presence || '(no description provided)'}

        Unified diff (truncated to #{diff.bytesize} bytes):
        ```diff
        #{diff}
        ```
      USER

      [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user",   content: user_content }
      ]
    end
  end
end
