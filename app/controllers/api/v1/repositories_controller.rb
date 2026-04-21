module Api
  module V1
    class RepositoriesController < Api::BaseController
      def index
        repos = current_user.repositories.order(created_at: :desc)
        render json: { repositories: repos.map { |r| serialize(r) } }
      end

      def show
        repo = current_user.repositories.find(params[:id])
        render json: { repository: serialize(repo, full: true) }
      end

      private

      def serialize(repo, full: false)
        base = {
          id:                   repo.id,
          full_name:            repo.full_name,
          indexing_status:      repo.indexing_status,
          embeddings_count:     repo.embeddings_count,
          pull_requests_count:  repo.pull_requests_count,
          last_indexed_at:      repo.last_indexed_at&.iso8601
        }
        return base unless full

        base.merge(
          owner:          repo.owner,
          name:           repo.name,
          default_branch: repo.default_branch,
          last_synced_at: repo.last_synced_at&.iso8601,
          created_at:     repo.created_at.iso8601,
          updated_at:     repo.updated_at.iso8601
        )
      end
    end
  end
end
