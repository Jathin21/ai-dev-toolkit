class CreatePullRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :pull_requests do |t|
      t.references :repository, null: false, foreign_key: true

      t.integer :number,     null: false           # GitHub PR number
      t.bigint  :github_id,  null: false
      t.string  :title,      null: false
      t.text    :body
      t.string  :state,      null: false           # open | closed | merged
      t.string  :author_login
      t.string  :base_ref
      t.string  :head_ref
      t.string  :head_sha

      t.integer :additions,      default: 0
      t.integer :deletions,      default: 0
      t.integer :changed_files,  default: 0

      # AI-generated artifacts
      t.text    :ai_summary
      t.text    :ai_review_notes
      t.jsonb   :ai_metadata, null: false, default: {}
      t.string  :ai_status,     null: false, default: "pending"  # pending | running | completed | failed
      t.datetime :ai_generated_at

      t.datetime :pr_created_at
      t.datetime :pr_updated_at
      t.datetime :pr_merged_at

      t.timestamps
    end

    add_index :pull_requests, %i[repository_id number], unique: true
    add_index :pull_requests, :github_id,               unique: true
    add_index :pull_requests, :state
    add_index :pull_requests, :ai_status
    add_index :pull_requests, :ai_metadata, using: :gin
  end
end
