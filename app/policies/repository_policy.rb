class RepositoryPolicy < ApplicationPolicy
  def index?   ; user.present?             ; end
  def show?    ; owned?                    ; end
  def create?  ; user.present?             ; end
  def update?  ; owned?                    ; end
  def destroy? ; owned?                    ; end
  def sync?    ; owned?                    ; end
  def reindex? ; owned?                    ; end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(user_id: user.id)
    end
  end

  private

  def owned?
    record.user_id == user.id
  end
end
