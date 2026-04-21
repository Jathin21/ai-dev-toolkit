module Api
  module V1
    class CodeSearchesController < Api::BaseController
      def create
        repository = current_user.repositories.find(params[:repository_id])
        query_text = params.require(:query).to_s.strip

        return render_error("query is blank", :bad_request)                     if query_text.empty?
        return render_error("repository not indexed", :conflict)                unless repository.indexed?

        limit    = [params.fetch(:limit, 10).to_i, 50].min
        language = params[:language].presence

        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        results = Embeddings::SemanticSearch.new(repository)
                                            .call(query_text, limit: limit, language: language)
        elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1_000).round

        current_user.code_searches.create!(
          repository:   repository,
          query_text:   query_text,
          results:      results.map(&:to_h),
          result_count: results.length,
          execution_ms: elapsed
        )

        render json: {
          query:        query_text,
          execution_ms: elapsed,
          results:      results.map(&:to_h)
        }
      end
    end
  end
end
