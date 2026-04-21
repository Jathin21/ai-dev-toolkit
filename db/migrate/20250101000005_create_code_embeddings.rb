class CreateCodeEmbeddings < ActiveRecord::Migration[7.1]
  def change
    create_table :code_embeddings do |t|
      t.references :repository, null: false, foreign_key: true

      t.string  :file_path,  null: false           # e.g. "app/models/user.rb"
      t.string  :language                          # "ruby", "python", ...
      t.string  :commit_sha, null: false           # commit the content was indexed from
      t.integer :chunk_index, null: false, default: 0
      t.integer :start_line, null: false, default: 1
      t.integer :end_line,   null: false, default: 1

      t.text :content,        null: false          # raw code chunk
      t.text :content_digest, null: false          # SHA256 of content — dedup + change-detection

      # Vector column. Dimension MUST match the configured embedding model.
      # text-embedding-3-small → 1536
      t.column :embedding, "vector(1536)", null: false

      t.integer :token_count, default: 0
      t.jsonb   :metadata,    null: false, default: {}

      t.timestamps
    end

    add_index :code_embeddings, %i[repository_id file_path chunk_index],
              unique: true, name: "idx_code_embeddings_unique_chunk"
    add_index :code_embeddings, :content_digest
    add_index :code_embeddings, :language

    # HNSW index for fast approximate nearest-neighbor search over the embedding column.
    # cosine distance (`vector_cosine_ops`) is the standard for OpenAI embeddings.
    execute <<~SQL.squish
      CREATE INDEX idx_code_embeddings_vector_hnsw
      ON code_embeddings
      USING hnsw (embedding vector_cosine_ops)
      WITH (m = 16, ef_construction = 64)
    SQL
  end
end
