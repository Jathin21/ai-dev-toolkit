class DeviseCreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users do |t|
      t.string  :email,              null: false, default: ""
      t.string  :encrypted_password, null: false, default: ""
      t.string  :name

      # Role-based access — :admin gates the Sidekiq web UI and dangerous queries.
      t.string  :role, null: false, default: "member"

      # Devise recoverable
      t.string   :reset_password_token
      t.datetime :reset_password_sent_at

      # Devise rememberable
      t.datetime :remember_created_at

      # Per-user GitHub PAT for private repo access (encrypted with AR encrypted attributes)
      t.text :encrypted_github_token

      t.timestamps null: false
    end

    add_index :users, :email,                unique: true
    add_index :users, :reset_password_token, unique: true
  end
end
