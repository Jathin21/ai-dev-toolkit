class Query < ApplicationRecord
  STATUSES = %w[pending running completed failed rejected].freeze

  belongs_to :user
  belongs_to :repository, optional: true

  validates :question, presence: true, length: { maximum: 2_000 }
  validates :status,   inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }

  def completed?
    status == "completed"
  end

  def rejected?
    status == "rejected"
  end
end
