class PagesController < ApplicationController
  def dashboard
    @repositories = current_user.repositories.order(created_at: :desc).limit(10)
    @recent_prs   = PullRequest.joins(:repository)
                               .where(repositories: { user_id: current_user.id })
                               .order(pr_updated_at: :desc)
                               .limit(10)
    @recent_queries  = current_user.queries.recent.limit(5)
    @recent_searches = current_user.code_searches.recent.limit(5)

    @stats = {
      repositories:       current_user.repositories.count,
      indexed:            current_user.repositories.ready_to_search.count,
      embeddings:         CodeEmbedding.joins(:repository).where(repositories: { user_id: current_user.id }).count,
      summaries:          PullRequest.joins(:repository)
                                    .where(repositories: { user_id: current_user.id }, ai_status: "completed")
                                    .count
    }
  end
end
