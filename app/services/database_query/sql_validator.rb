module DatabaseQuery
  # Defense in depth for user-facing natural-language-to-SQL.
  #
  # Even though we execute every generated query through a read-only Postgres
  # role, we ALSO statically validate the SQL string before sending it to the
  # database. The goal is to reject anything that:
  #
  #   1. mutates data (INSERT/UPDATE/DELETE/TRUNCATE/DROP/ALTER/CREATE/GRANT/...)
  #   2. references tables outside our explicit allow-list
  #   3. chains multiple statements (stacked queries)
  #
  # We treat the LLM as *untrusted input*. Any prompt-injection that gets past
  # the system prompt hits this validator next. Defense in depth is not paranoid
  # here — it's the floor.
  class SqlValidator
    class InvalidSqlError < StandardError; end

    # Only these tables may be queried by the NL-to-SQL feature.
    ALLOWED_TABLES = %w[
      repositories
      pull_requests
      code_embeddings
      queries
      code_searches
    ].freeze

    FORBIDDEN_KEYWORDS = %w[
      INSERT UPDATE DELETE TRUNCATE DROP ALTER CREATE GRANT REVOKE
      VACUUM ANALYZE REINDEX CLUSTER COPY LOCK
      CALL EXECUTE DO DECLARE
      SET RESET
      COMMIT ROLLBACK SAVEPOINT RELEASE
    ].freeze

    def self.validate!(sql)
      raise InvalidSqlError, "SQL is blank" if sql.to_s.strip.empty?

      normalized = strip_comments(sql).strip

      # Reject stacked queries. We split on semicolons that aren't inside
      # string literals. A trailing semicolon is fine; two statements aren't.
      statements = split_statements(normalized)
      raise InvalidSqlError, "Multiple statements are not allowed" if statements.size > 1

      stmt = statements.first.to_s.strip
      raise InvalidSqlError, "Only SELECT and WITH queries are allowed" unless stmt.match?(/\A(SELECT|WITH)\b/i)

      upper = stmt.upcase
      FORBIDDEN_KEYWORDS.each do |kw|
        if upper.match?(/\b#{Regexp.escape(kw)}\b/)
          raise InvalidSqlError, "Forbidden keyword detected: #{kw}"
        end
      end

      referenced = extract_table_refs(upper)
      disallowed = referenced - ALLOWED_TABLES.map(&:upcase)
      if disallowed.any?
        raise InvalidSqlError, "Query references tables outside allow-list: #{disallowed.join(', ')}"
      end

      true
    end

    def self.strip_comments(sql)
      # Remove both -- line comments and /* block */ comments. This runs BEFORE
      # keyword scanning so an attacker can't hide DROP TABLE inside /* ... */.
      sql.to_s
         .gsub(%r{/\*.*?\*/}m, " ")
         .gsub(/--[^\n]*/, " ")
    end

    def self.split_statements(sql)
      out = []
      buf = +""
      in_single = in_double = false
      sql.each_char do |c|
        case c
        when "'" then in_single = !in_single unless in_double
        when '"' then in_double = !in_double unless in_single
        when ";"
          unless in_single || in_double
            out << buf.strip unless buf.strip.empty?
            buf = +""
            next
          end
        end
        buf << c
      end
      out << buf.strip unless buf.strip.empty?
      out
    end

    # Extracts likely table identifiers by scanning for tokens after FROM / JOIN.
    # This is intentionally conservative — false positives are fine (they just
    # cause rejection), false negatives are not.
    def self.extract_table_refs(upper_sql)
      upper_sql.scan(/\b(?:FROM|JOIN)\s+([A-Z_][A-Z0-9_]*)/).flatten.uniq
    end
  end
end
