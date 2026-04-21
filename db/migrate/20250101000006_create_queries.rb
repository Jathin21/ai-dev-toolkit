class CreateQueries < ActiveRecord::Migration[7.1]
  def change
    create_table :queries do |t|
      t.references :user,       null: false, foreign_key: true
      t.references :repository, null: true,  foreign_key: true

      t.text   :question,    null: false         # natural-language input
      t.text   :generated_sql                    # SQL produced by the LLM
      t.jsonb  :result_rows, null: false, default: []
      t.jsonb  :result_columns, null: false, default: []
      t.text   :explanation                      # LLM-generated explanation of results
      t.string :status,      null: false, default: "pending"  # pending | running | completed | failed | rejected
      t.text   :error_message

      t.integer :execution_ms
      t.integer :row_count,   default: 0

      t.timestamps
    end

    add_index :queries, %i[user_id created_at]
    add_index :queries, :status
  end
end
