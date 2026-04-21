class CreateRepositories < ActiveRecord::Migration[7.1]
  def change
    create_table :repositories do |t|
      t.references :user, null: false, foreign_key: true

      t.string  :name,           null: false         # e.g. "rails"
      t.string  :owner,          null: false         # e.g. "rails"
      t.string  :full_name,      null: false         # e.g. "rails/rails"
      t.string  :default_branch, null: false, default: "main"
      t.string  :clone_url
      t.bigint  :github_id

      t.string   :indexing_status, null: false, default: "pending"   # pending | running | completed | failed
      t.datetime :last_synced_at
      t.datetime :last_indexed_at
      t.text     :last_error

      t.integer :embeddings_count,    null: false, default: 0
      t.integer :pull_requests_count, null: false, default: 0

      t.timestamps
    end

    add_index :repositories, :full_name, unique: true
    add_index :repositories, :indexing_status
    add_index :repositories, %i[user_id created_at]
  end
end
