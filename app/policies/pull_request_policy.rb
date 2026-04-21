class PullRequestPolicy < ApplicationPolicy
  def index?     ; repo_owned? ; end
  def show?      ; repo_owned? ; end
  def summarize? ; repo_owned? ; end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.joins(:repository).where(repositories: { user_id: user.id })
    end
  end

  private

  def repo_owned?
    record.repository.user_id == user.id
  end
end
