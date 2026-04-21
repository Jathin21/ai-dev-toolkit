class ReindexStaleEmbeddingsJob < ApplicationJob
  queue_as :indexing

  def perform
    Repository.ready_to_search.stale.find_each do |repo|
      IndexRepositoryJob.perform_later(repo.id)
    end
  end
end
