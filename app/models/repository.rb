class Repository < ApplicationRecord
  INDEXING_STATUSES = %w[pending running completed failed].freeze

  belongs_to :user
  has_many :pull_requests,   dependent: :destroy
  has_many :code_embeddings, dependent: :delete_all
  has_many :queries,         dependent: :nullify
  has_many :code_searches,   dependent: :destroy

  validates :full_name,  presence: true, uniqueness: true,
                         format: { with: %r{\A[^/\s]+/[^/\s]+\z}, message: "must be owner/name" }
  validates :name, :owner, presence: true
  validates :indexing_status, inclusion: { in: INDEXING_STATUSES }

  before_validation :parse_full_name

  scope :ready_to_search, -> { where(indexing_status: "completed") }
  scope :stale,           ->(threshold = 30.days.ago) { where("last_indexed_at < ? OR last_indexed_at IS NULL", threshold) }

  def indexed?
    indexing_status == "completed" && last_indexed_at.present?
  end

  def indexing!
    update!(indexing_status: "running")
  end

  def mark_indexed!
    update!(
      indexing_status:   "completed",
      last_indexed_at:   Time.current,
      embeddings_count:  code_embeddings.count,
      last_error:        nil
    )
  end

  def mark_failed!(error)
    update!(indexing_status: "failed", last_error: error.to_s.truncate(2_000))
  end

  private

  def parse_full_name
    return if full_name.blank?

    parts = full_name.split("/", 2)
    self.owner ||= parts.first
    self.name  ||= parts.last
  end
end
