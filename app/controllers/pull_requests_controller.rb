class PullRequestsController < ApplicationController
  before_action :set_repository
  before_action :set_pull_request, only: %i[show summarize]

  def index
    scope  = @repository.pull_requests
    scope  = scope.where(state: params[:state]) if params[:state].in?(%w[open closed merged])
    @pull_requests = scope.order(pr_updated_at: :desc).page(params[:page])
  end

  def show
  end

  def summarize
    SummarizePullRequestJob.perform_later(@pull_request.id)
    @pull_request.update!(ai_status: "pending") if @pull_request.ai_status == "failed"

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "pull_request_#{@pull_request.id}_summary",
          partial: "pull_requests/summary",
          locals:  { pull_request: @pull_request }
        )
      end
      format.html { redirect_to [@repository, @pull_request], notice: "AI summary queued." }
    end
  end

  private

  def set_repository
    @repository = current_user.repositories.find(params[:repository_id])
  end

  def set_pull_request
    @pull_request = @repository.pull_requests.find(params[:id])
  end
end
