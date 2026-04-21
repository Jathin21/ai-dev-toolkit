module DatabaseQuery
  # Produces a compact schema description suitable for embedding in the
  # NL-to-SQL system prompt. We deliberately don't just dump the full schema —
  # we present only the allow-listed tables and a hand-curated set of columns,
  # so the model never learns that tables like `users.encrypted_password`
  # exist in the first place.
  class SchemaDescriber
    SCHEMA = {
      "repositories" => {
        description: "Tracked GitHub repositories and their indexing state.",
        columns: {
          "id"                 => "bigint primary key",
          "full_name"          => "text — 'owner/name', e.g. 'rails/rails'",
          "owner"              => "text",
          "name"               => "text",
          "default_branch"     => "text",
          "indexing_status"    => "text — pending|running|completed|failed",
          "last_synced_at"     => "timestamp",
          "last_indexed_at"    => "timestamp",
          "embeddings_count"   => "integer",
          "pull_requests_count"=> "integer",
          "created_at"         => "timestamp",
          "updated_at"         => "timestamp"
        }
      },
      "pull_requests" => {
        description: "Pull requests synced from GitHub, plus AI-generated summaries.",
        columns: {
          "id"              => "bigint primary key",
          "repository_id"   => "bigint references repositories(id)",
          "number"          => "integer — PR number on GitHub",
          "title"           => "text",
          "state"           => "text — open|closed|merged",
          "author_login"    => "text",
          "additions"       => "integer",
          "deletions"       => "integer",
          "changed_files"   => "integer",
          "ai_status"       => "text — pending|running|completed|failed",
          "ai_summary"      => "text",
          "ai_metadata"     => "jsonb — includes risk_level, areas[], test_coverage",
          "pr_created_at"   => "timestamp",
          "pr_merged_at"    => "timestamp"
        }
      },
      "code_embeddings" => {
        description: "Vector embeddings of source code chunks. Do NOT select the `embedding` or `content` columns in analytical queries — they are large.",
        columns: {
          "id"              => "bigint primary key",
          "repository_id"   => "bigint references repositories(id)",
          "file_path"       => "text",
          "language"        => "text",
          "commit_sha"      => "text",
          "chunk_index"     => "integer",
          "start_line"      => "integer",
          "end_line"        => "integer",
          "token_count"     => "integer",
          "created_at"      => "timestamp"
        }
      },
      "queries" => {
        description: "Audit log of previous natural-language database queries.",
        columns: {
          "id"             => "bigint primary key",
          "user_id"        => "bigint",
          "question"       => "text",
          "generated_sql"  => "text",
          "status"         => "text",
          "row_count"      => "integer",
          "execution_ms"   => "integer",
          "created_at"     => "timestamp"
        }
      },
      "code_searches" => {
        description: "Audit log of semantic code searches.",
        columns: {
          "id"             => "bigint primary key",
          "user_id"        => "bigint",
          "repository_id"  => "bigint",
          "query_text"     => "text",
          "result_count"   => "integer",
          "execution_ms"   => "integer",
          "created_at"     => "timestamp"
        }
      }
    }.freeze

    def self.prompt_text
      lines = ["You have read-only access to the following Postgres tables."]
      SCHEMA.each do |table, info|
        lines << ""
        lines << "TABLE #{table} — #{info[:description]}"
        info[:columns].each { |col, desc| lines << "  #{col}: #{desc}" }
      end
      lines << ""
      lines << "Tables NOT listed here are off-limits. Do not reference them."
      lines.join("\n")
    end
  end
end
