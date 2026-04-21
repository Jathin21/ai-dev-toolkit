class CodeSearchesController < ApplicationController
  before_action :set_repository

  def index
    @recent_searches = current_user.code_searches
                                   .where(repository: @repository)
                                   .recent
                                   .limit(20)
  end

  def create
    query_text = params.require(:query_text).to_s.strip
    if query_text.empty?
      return redirect_to(repository_code_searches_path(@repository), alert: "Query is blank.")
    end

    unless @repository.indexed?
      return redirect_to(@repository, alert: "This repository isn't indexed yet.")
    end

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    results = Embeddings::SemanticSearch.new(@repository).call(query_text, limit: 10)
    elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1_000).round

    @search = current_user.code_searches.create!(
      repository:   @repository,
      query_text:   query_text,
      results:      results.map(&:to_h),
      result_count: results.length,
      execution_ms: elapsed
    )

    @results = results

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          "search_results",
          partial: "code_searches/results",
          locals:  { search: @search, results: @results }
        )
      end
      format.html { render :index }
    end
  end
end
