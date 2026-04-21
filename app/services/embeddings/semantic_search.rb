module Embeddings
  # Executes a semantic code search: embed the query, then use pgvector's
  # HNSW index (via the `neighbor` gem) to find the most cosine-similar chunks.
  #
  # Typical latency on a 100k-chunk repo: ~50-150ms for the ANN lookup,
  # plus ~200-400ms for the query embedding — well under the "sub-second
  # interactive queries" target.
  class SemanticSearch
    Result = Struct.new(
      :embedding_id, :file_path, :language, :start_line, :end_line,
      :preview, :distance, :similarity,
      keyword_init: true
    )

    DEFAULT_LIMIT = 10

    def initialize(repository, ai_client: AI::Client.new)
      @repository = repository
      @ai_client  = ai_client
    end

    def call(query_text, limit: DEFAULT_LIMIT, language: nil)
      raise ArgumentError, "query_text is blank" if query_text.to_s.strip.empty?

      query_vec = @ai_client.embed(query_text)

      scope = @repository.code_embeddings
      scope = scope.where(language: language) if language.present?

      # `nearest_neighbors` comes from `has_neighbors :embedding` in the model.
      # `neighbor_distance` is an AR virtual attribute populated by the gem.
      records = scope
                .nearest_neighbors(:embedding, query_vec, distance: :cosine)
                .limit(limit)

      records.map do |rec|
        distance = rec.neighbor_distance.to_f
        Result.new(
          embedding_id: rec.id,
          file_path:    rec.file_path,
          language:     rec.language,
          start_line:   rec.start_line,
          end_line:     rec.end_line,
          preview:      rec.preview,
          distance:     distance,
          similarity:   (1.0 - distance).round(4)  # cosine distance → similarity
        )
      end
    end
  end
end
