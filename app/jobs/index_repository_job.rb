class IndexRepositoryJob < ApplicationJob
  queue_as :indexing

  # A single repo's indexing should never run twice in parallel — it wastes
  # OpenAI credits and can deadlock on the unique index. Sidekiq's :lock_key
  # option via sidekiq-unique-jobs would be cleaner in a larger app; here we
  # use the `indexing_status` column as the guard.
  def perform(repository_id)
    repository = Repository.find(repository_id)
    return if repository.indexing_status == "running"

    stats = Embeddings::Indexer.new(repository).call
    Rails.logger.info(
      "[IndexRepositoryJob] repository=#{repository.full_name} " \
      "files=#{stats[:files_seen]} chunks=#{stats[:chunks_created]} " \
      "skipped=#{stats[:chunks_skipped]} api_calls=#{stats[:api_calls]}"
    )
  end
end
