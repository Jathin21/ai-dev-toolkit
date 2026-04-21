class SyncAllRepositoriesJob < ApplicationJob
  queue_as :default

  def perform
    Repository.where.not(indexing_status: "running").find_each do |repo|
      SyncRepositoryJob.perform_later(repo.id)
    end
  end
end
