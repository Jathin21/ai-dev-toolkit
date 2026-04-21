class RepositoriesController < ApplicationController
  before_action :set_repository, only: %i[show sync reindex destroy]

  def index
    @repositories = current_user.repositories.order(created_at: :desc)
  end

  def show
    @pull_requests = @repository.pull_requests.order(pr_updated_at: :desc).limit(25)
  end

  def new
    @repository = current_user.repositories.build
  end

  def create
    @repository = current_user.repositories.build(repository_params)

    # Enrich with GitHub metadata before saving so `name`, `owner`, `default_branch`
    # always match reality.
    begin
      meta = Github::Client.new(token: current_user.github_token).repo_metadata(@repository.full_name)
      @repository.assign_attributes(meta)
    rescue Github::Client::NotFoundError
      @repository.errors.add(:full_name, "not found on GitHub or not accessible with your token")
      return render :new, status: :unprocessable_entity
    rescue Github::Client::AuthError => e
      @repository.errors.add(:base, "GitHub auth failed: #{e.message}")
      return render :new, status: :unprocessable_entity
    end

    if @repository.save
      SyncRepositoryJob.perform_later(@repository.id)
      IndexRepositoryJob.perform_later(@repository.id)
      redirect_to @repository, notice: "Repository added. Indexing has started in the background."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def sync
    SyncRepositoryJob.perform_later(@repository.id)
    redirect_to @repository, notice: "Sync queued."
  end

  def reindex
    IndexRepositoryJob.perform_later(@repository.id)
    redirect_to @repository, notice: "Reindex queued."
  end

  def destroy
    @repository.destroy
    redirect_to repositories_path, notice: "Repository removed."
  end

  private

  def set_repository
    @repository = current_user.repositories.find(params[:id])
  end

  def repository_params
    params.require(:repository).permit(:full_name)
  end
end
