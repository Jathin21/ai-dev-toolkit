class QueriesController < ApplicationController
  before_action :set_repository
  before_action :set_query, only: :show

  def index
    @queries = current_user.queries.where(repository: @repository).recent.limit(20)
  end

  def show
  end

  def create
    question = params.require(:question).to_s.strip
    if question.empty?
      return redirect_to(repository_queries_path(@repository), alert: "Question is blank.")
    end

    @query = current_user.queries.create!(
      repository: @repository,
      question:   question,
      status:     "pending"
    )

    begin
      DatabaseQuery::NaturalLanguageExecutor.new(@query).call
    rescue DatabaseQuery::NaturalLanguageExecutor::RejectedError
      # Already recorded on @query — fall through to render.
    rescue StandardError => e
      Rails.logger.error("[QueriesController#create] #{e.class}: #{e.message}")
    end

    @query.reload

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          "query_result",
          partial: "queries/result",
          locals:  { query: @query }
        )
      end
      format.html { redirect_to repository_query_path(@repository, @query) }
    end
  end

  private

  def set_repository
    @repository = current_user.repositories.find(params[:repository_id])
  end

  def set_query
    @query = current_user.queries.find(params[:id])
  end
end
