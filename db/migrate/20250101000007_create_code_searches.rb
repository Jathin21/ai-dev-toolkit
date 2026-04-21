class CreateCodeSearches < ActiveRecord::Migration[7.1]
  def change
    create_table :code_searches do |t|
      t.references :user,       null: false, foreign_key: true
      t.references :repository, null: false, foreign_key: true

      t.text    :query_text,   null: false
      t.jsonb   :results,      null: false, default: []
      t.integer :result_count, default: 0
      t.integer :execution_ms

      t.timestamps
    end

    add_index :code_searches, %i[user_id created_at]
    add_index :code_searches, %i[repository_id created_at]
  end
end
