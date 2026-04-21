class SummarizePullRequestJob < ApplicationJob
  queue_as :ai

  def perform(pull_request_id)
    pr = PullRequest.find(pull_request_id)
    return if pr.ai_status == "running"

    AI::PRSummarizer.new(pr).call

    # Push the updated PR row to anyone watching the show page via Turbo Streams.
    Turbo::StreamsChannel.broadcast_replace_to(
      "pull_request_#{pr.id}",
      target: "pull_request_#{pr.id}_summary",
      partial: "pull_requests/summary",
      locals:  { pull_request: pr }
    )
  end
end
