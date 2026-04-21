class PullRequest < ApplicationRecord
  STATES      = %w[open closed merged].freeze
  AI_STATUSES = %w[pending running completed failed].freeze

  belongs_to :repository

  validates :number,    presence: true, uniqueness: { scope: :repository_id }
  validates :github_id, presence: true, uniqueness: true
  validates :title,     presence: true
  validates :state,     inclusion: { in: STATES }
  validates :ai_status, inclusion: { in: AI_STATUSES }

  scope :open_prs,        -> { where(state: "open") }
  scope :recently_merged, -> { where(state: "merged").where("pr_merged_at > ?", 30.days.ago) }
  scope :awaiting_ai,     -> { where(ai_status: %w[pending failed]) }

  def ai_summary_ready?
    ai_status == "completed" && ai_summary.present?
  end

  def ai_running!
    update!(ai_status: "running")
  end

  def mark_ai_complete!(summary:, review_notes:, metadata: {})
    update!(
      ai_status:        "completed",
      ai_summary:       summary,
      ai_review_notes:  review_notes,
      ai_metadata:      metadata,
      ai_generated_at:  Time.current
    )
  end

  def mark_ai_failed!(error)
    update!(ai_status: "failed", ai_metadata: ai_metadata.merge(last_error: error.to_s.truncate(500)))
  end
end
