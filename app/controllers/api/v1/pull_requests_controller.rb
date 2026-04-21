module Api
  module V1
    class PullRequestsController < Api::BaseController
      before_action :set_repository
      before_action :set_pull_request, only: %i[show summarize]

      def index
        scope = @repository.pull_requests
        scope = scope.where(state: params[:state]) if params[:state].in?(%w[open closed merged])

        per_page = [params.fetch(:per_page, 25).to_i, 100].min
        page     = params.fetch(:page, 1).to_i

        total = scope.count
        prs   = scope.order(pr_updated_at: :desc).offset((page - 1) * per_page).limit(per_page)

        render json: {
          pull_requests: prs.map { |pr| serialize(pr) },
          page:          page,
          total_pages:   (total.to_f / per_page).ceil
        }
      end

      def show
        render json: { pull_request: serialize(@pull_request, full: true) }
      end

      def summarize
        job = SummarizePullRequestJob.perform_later(@pull_request.id)
        @pull_request.update!(ai_status: "pending") if @pull_request.ai_status == "failed"
        render json: { ai_status: @pull_request.ai_status, job_id: job.job_id }, status: :accepted
      end

      private

      def set_repository
        @repository = current_user.repositories.find(params[:repository_id])
      end

      def set_pull_request
        @pull_request = @repository.pull_requests.find(params[:id])
      end

      def serialize(pr, full: false)
        base = {
          id:             pr.id,
          number:         pr.number,
          title:          pr.title,
          state:          pr.state,
          author_login:   pr.author_login,
          ai_status:      pr.ai_status,
          additions:      pr.additions,
          deletions:      pr.deletions,
          changed_files:  pr.changed_files,
          pr_merged_at:   pr.pr_merged_at&.iso8601,
          pr_updated_at:  pr.pr_updated_at&.iso8601
        }
        return base unless full

        base.merge(
          body:            pr.body,
          ai_summary:      pr.ai_summary,
          ai_review_notes: pr.ai_review_notes,
          ai_metadata:     pr.ai_metadata,
          ai_generated_at: pr.ai_generated_at&.iso8601
        )
      end
    end
  end
end
