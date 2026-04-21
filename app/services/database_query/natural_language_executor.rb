module DatabaseQuery
  # Orchestrates: NL question → SQL generation → static validation → read-only
  # execution → result formatting → natural-language explanation.
  #
  # Every SELECT is executed with `statement_timeout=5s` and wrapped in a
  # transaction that's rolled back on exit, even for pure SELECTs. The
  # `statement_timeout` is the hard ceiling: a runaway `SELECT COUNT(*) FROM a
  # CROSS JOIN b` can't take the database down.
  class NaturalLanguageExecutor
    class RejectedError < StandardError; end

    SYSTEM_PROMPT_TEMPLATE = <<~PROMPT
      You are a SQL generator for a read-only Postgres database.

      %<schema>s

      RULES:
      - Generate exactly ONE SQL statement. No semicolons except at the end.
      - Only SELECT or WITH ... SELECT queries. No INSERT/UPDATE/DELETE/DDL.
      - Always add a reasonable LIMIT (default 100) unless the user asked for a specific aggregate.
      - Never SELECT embedding or content columns from code_embeddings.
      - Use Postgres-standard syntax.
      - Output ONLY the SQL. No markdown fences, no commentary, no explanation.
    PROMPT

    STATEMENT_TIMEOUT_MS = 5_000
    MAX_ROWS             = 500

    def initialize(query_record, ai_client: AI::Client.new)
      @query     = query_record
      @ai_client = ai_client
    end

    def call
      @query.update!(status: "running")
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      sql = generate_sql(@query.question)
      SqlValidator.validate!(sql)

      rows, columns = execute_read_only(sql)

      explanation = explain_results(sql, columns, rows)

      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1_000).round
      @query.update!(
        status:          "completed",
        generated_sql:   sql,
        result_columns:  columns,
        result_rows:     rows,
        row_count:       rows.length,
        execution_ms:    elapsed_ms,
        explanation:     explanation
      )
      @query
    rescue SqlValidator::InvalidSqlError => e
      @query.update!(status: "rejected", error_message: e.message)
      raise RejectedError, e.message
    rescue ActiveRecord::StatementInvalid => e
      @query.update!(status: "failed", error_message: e.message.truncate(500))
      raise
    end

    private

    def generate_sql(question)
      system = format(SYSTEM_PROMPT_TEMPLATE, schema: SchemaDescriber.prompt_text)
      raw = @ai_client.chat(
        messages: [
          { role: "system", content: system },
          { role: "user",   content: question }
        ],
        temperature: 0.0,
        max_tokens:  700
      )

      # Defensive: strip markdown fences even though we told the model not to use them.
      raw.to_s.strip.sub(/\A```(?:sql)?/i, "").sub(/```\z/, "").strip
    end

    # Runs the query under a short statement_timeout in a transaction that is
    # always rolled back — even a validated SELECT shouldn't leave side effects
    # (e.g. if the model somehow produces a CTE containing a function call).
    def execute_read_only(sql)
      rows    = []
      columns = []

      ActiveRecord::Base.transaction(requires_new: true) do
        ActiveRecord::Base.connection.execute("SET LOCAL statement_timeout = #{STATEMENT_TIMEOUT_MS}")
        ActiveRecord::Base.connection.execute("SET LOCAL transaction_read_only = on")

        result  = ActiveRecord::Base.connection.exec_query(sql)
        columns = result.columns
        rows    = result.rows.first(MAX_ROWS).map { |r| normalize_row(r) }

        raise ActiveRecord::Rollback
      end

      [rows, columns]
    end

    def normalize_row(row)
      row.map do |val|
        case val
        when Time, Date, DateTime then val.iso8601
        when BigDecimal           then val.to_f
        else val
        end
      end
    end

    def explain_results(sql, columns, rows)
      prompt = <<~USER
        Original question: #{@query.question}

        SQL executed:
        #{sql}

        Columns: #{columns.join(', ')}
        First rows: #{rows.first(5).inspect}
        Total rows returned: #{rows.length}

        Explain the result in 1-2 sentences of plain English. Do not restate the SQL.
      USER

      @ai_client.chat(
        messages: [
          { role: "system", content: "You summarize SQL query results for non-technical users." },
          { role: "user",   content: prompt }
        ],
        temperature: 0.2,
        max_tokens:  250
      )
    rescue StandardError
      # Explanation is nice-to-have — never fail the whole query on its behalf.
      nil
    end
  end
end
