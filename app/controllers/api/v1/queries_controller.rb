module Api
  module V1
    class QueriesController < Api::BaseController
      def create
        repository = current_user.repositories.find(params[:repository_id])
        question   = params.require(:question).to_s.strip

        return render_error("question is blank", :bad_request) if question.empty?

        query = current_user.queries.create!(
          repository: repository,
          question:   question,
          status:     "pending"
        )

        status = :ok
        begin
          DatabaseQuery::NaturalLanguageExecutor.new(query).call
        rescue DatabaseQuery::NaturalLanguageExecutor::RejectedError
          status = :unprocessable_entity
        rescue StandardError => e
          Rails.logger.error("[Api::V1::QueriesController] #{e.class}: #{e.message}")
          status = :internal_server_error
        end

        query.reload
        render json: { query: serialize(query) }, status: status
      end

      private

      def serialize(q)
        {
          id:              q.id,
          status:          q.status,
          question:        q.question,
          generated_sql:   q.generated_sql,
          result_columns:  q.result_columns,
          result_rows:     q.result_rows,
          row_count:       q.row_count,
          execution_ms:    q.execution_ms,
          explanation:     q.explanation,
          error_message:   q.error_message,
          created_at:      q.created_at.iso8601
        }
      end
    end
  end
end
