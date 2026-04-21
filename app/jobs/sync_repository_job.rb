class SyncRepositoryJob < ApplicationJob
  queue_as :default

  def perform(repository_id)
    repository = Repository.find(repository_id)
    client     = Github::Client.new(token: repository.user.github_token)

    # On incremental syncs, only fetch PRs updated since the last sync.
    since = repository.last_synced_at

    client.each_pull_request(repository.full_name, state: "all", since: since) do |pr_data|
      record = PullRequest.find_or_initialize_by(
        repository_id: repository.id,
        number:        pr_data[:number]
      )
      record.assign_attributes(pr_data)
      record.save!

      # Queue an AI summary for freshly-opened PRs (cheap and useful),
      # but skip ones we've already summarized unless the head_sha changed.
      if record.saved_change_to_head_sha? || record.ai_status == "pending"
        SummarizePullRequestJob.perform_later(record.id)
      end
    end

    repository.update!(last_synced_at: Time.current, pull_requests_count: repository.pull_requests.count)
  end
end
