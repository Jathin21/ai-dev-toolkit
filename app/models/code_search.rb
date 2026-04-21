class CodeSearch < ApplicationRecord
  belongs_to :user
  belongs_to :repository

  validates :query_text, presence: true, length: { maximum: 1_000 }

  scope :recent, -> { order(created_at: :desc) }
end
