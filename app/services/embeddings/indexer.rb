module Embeddings
  # Walks a repository's source tree, chunks each file, batches the chunks
  # through the OpenAI embeddings endpoint, and upserts the resulting vectors
  # into code_embeddings. Designed to be *idempotent* and *incremental*:
  #
  #   - We compute a SHA256 digest of each chunk's content.
  #   - Before embedding, we check whether a row with the same
  #     (repository_id, file_path, chunk_index, content_digest) already exists.
  #   - If it does, we skip the API call entirely. This matters: re-indexing
  #     a 10k-file repo after a 3-file change should cost pennies, not dollars.
  class Indexer
    BATCH_SIZE = 96   # OpenAI allows up to 2048 embeddings per request; 96 is a
                      # conservative batch size that keeps individual requests
                      # under timeout limits for large chunks.

    attr_reader :repository, :stats

    def initialize(repository, ai_client: AI::Client.new, github_client: nil, chunker: Chunker.new)
      @repository    = repository
      @ai_client     = ai_client
      @github_client = github_client || Github::Client.new(token: repository.user.github_token)
      @chunker       = chunker
      @stats         = { files_seen: 0, chunks_created: 0, chunks_skipped: 0, api_calls: 0 }
    end

    # Top-level entry. Called from IndexRepositoryJob.
    def call
      @repository.indexing!

      pending = []   # accumulates chunks awaiting embedding in the current batch
      @github_client.each_source_file(@repository.full_name) do |path, content, commit_sha|
        @stats[:files_seen] += 1

        @chunker.chunk(content).each_with_index do |chunk, idx|
          digest   = CodeEmbedding.digest_for(chunk.content)
          existing = @repository.code_embeddings
                                .where(file_path: path, chunk_index: idx)
                                .pick(:content_digest)

          if existing == digest
            @stats[:chunks_skipped] += 1
            next
          end

          pending << {
            chunk:      chunk,
            path:       path,
            idx:        idx,
            digest:     digest,
            language:   Github::SourceFileFilter.language_for(path),
            commit_sha: commit_sha
          }

          flush_batch!(pending) if pending.size >= BATCH_SIZE
        end
      end

      flush_batch!(pending) if pending.any?
      @repository.mark_indexed!
      @stats
    rescue StandardError => e
      @repository.mark_failed!(e)
      raise
    end

    private

    # Embeds an entire batch in ONE API call and upserts all rows in a single
    # transaction. `insert_all` with `on_conflict` gives us atomic upsert.
    def flush_batch!(pending)
      return if pending.empty?

      inputs  = pending.map { |p| p[:chunk].content }
      vectors = @ai_client.embed(inputs)
      @stats[:api_calls] += 1

      rows = pending.each_with_index.map do |p, i|
        {
          repository_id:  @repository.id,
          file_path:      p[:path],
          language:       p[:language],
          commit_sha:     p[:commit_sha],
          chunk_index:    p[:idx],
          start_line:     p[:chunk].start_line,
          end_line:       p[:chunk].end_line,
          content:        p[:chunk].content,
          content_digest: p[:digest],
          embedding:      vectors[i],
          token_count:    p[:chunk].token_count,
          metadata:       {},
          created_at:     Time.current,
          updated_at:     Time.current
        }
      end

      CodeEmbedding.upsert_all(
        rows,
        unique_by: :idx_code_embeddings_unique_chunk,
        update_only: %i[content content_digest embedding commit_sha start_line end_line token_count updated_at]
      )

      @stats[:chunks_created] += pending.size
      pending.clear
    end
  end
end
