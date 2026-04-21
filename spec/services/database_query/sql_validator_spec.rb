require "rails_helper"

RSpec.describe DatabaseQuery::SqlValidator do
  describe ".validate!" do
    subject(:validate) { described_class.validate!(sql) }

    context "with benign SELECT queries" do
      [
        "SELECT * FROM repositories",
        "SELECT id, title FROM pull_requests WHERE state = 'merged' LIMIT 10",
        "SELECT COUNT(*) FROM code_embeddings",
        "SELECT r.full_name, COUNT(pr.id) FROM repositories r JOIN pull_requests pr ON pr.repository_id = r.id GROUP BY r.full_name",
        "WITH recent AS (SELECT * FROM pull_requests WHERE pr_merged_at > NOW() - INTERVAL '7 days') SELECT COUNT(*) FROM recent",
        "SELECT * FROM repositories;"   # trailing semicolon is fine
      ].each do |good_sql|
        it "allows: #{good_sql.truncate(60)}" do
          let(:sql) { good_sql }
          expect(described_class.validate!(good_sql)).to eq(true)
        end
      end
    end

    context "with mutations" do
      [
        ["bare INSERT",    "INSERT INTO users (email) VALUES ('x@x.com')"],
        ["bare UPDATE",    "UPDATE users SET role='admin' WHERE id=1"],
        ["bare DELETE",    "DELETE FROM users"],
        ["TRUNCATE",       "TRUNCATE TABLE users"],
        ["DROP",           "DROP TABLE users"],
        ["ALTER",          "ALTER TABLE users ADD COLUMN backdoor text"],
        ["CREATE",         "CREATE TABLE shadow (id int)"],
        ["GRANT",          "GRANT ALL ON users TO PUBLIC"],
        ["COPY",           "COPY users TO '/tmp/exfil.csv'"],
        ["EXECUTE",        "EXECUTE some_function()"],
        ["SET",            "SET statement_timeout = 0"],
        ["ROLLBACK",       "ROLLBACK"]
      ].each do |name, bad_sql|
        it "rejects #{name}" do
          expect { described_class.validate!(bad_sql) }
            .to raise_error(described_class::InvalidSqlError)
        end
      end
    end

    context "with stacked / chained statements (classic SQLi)" do
      [
        "SELECT 1; DROP TABLE users",
        "SELECT * FROM repositories; DELETE FROM pull_requests",
        "SELECT 1;;DROP TABLE users"
      ].each do |bad_sql|
        it "rejects stacked statement: #{bad_sql.truncate(40)}" do
          expect { described_class.validate!(bad_sql) }
            .to raise_error(described_class::InvalidSqlError, /multiple/i)
            .or raise_error(described_class::InvalidSqlError)
        end
      end

      it "is NOT fooled by a semicolon inside a string literal" do
        sql = "SELECT * FROM repositories WHERE full_name = '; DROP TABLE users'"
        expect(described_class.validate!(sql)).to eq(true)
      end
    end

    context "with SQL comments hiding malicious payloads" do
      it "strips block comments BEFORE keyword scanning" do
        sql = "/* DROP TABLE users */ SELECT 1 FROM repositories"
        # The validator should strip the comment first, then see no DROP, and allow it.
        expect(described_class.validate!(sql)).to eq(true)
      end

      it "catches DROP hidden AFTER comment stripping" do
        sql = "SELECT 1 FROM repositories; -- then the real payload\nDROP TABLE users"
        expect { described_class.validate!(sql) }
          .to raise_error(described_class::InvalidSqlError)
      end

      it "strips line comments BEFORE keyword scanning" do
        sql = "SELECT * FROM repositories -- DROP TABLE users"
        expect(described_class.validate!(sql)).to eq(true)
      end
    end

    context "with off-allow-list tables" do
      [
        "SELECT email, encrypted_password FROM users",
        "SELECT * FROM secrets",
        "SELECT r.* FROM repositories r JOIN users u ON u.id = r.user_id",
        "SELECT * FROM pg_catalog.pg_tables"
      ].each do |bad_sql|
        it "rejects reference to disallowed table: #{bad_sql.truncate(60)}" do
          expect { described_class.validate!(bad_sql) }
            .to raise_error(described_class::InvalidSqlError)
        end
      end
    end

    context "with edge cases" do
      it "rejects blank SQL" do
        expect { described_class.validate!("") }.to raise_error(described_class::InvalidSqlError)
        expect { described_class.validate!("   ") }.to raise_error(described_class::InvalidSqlError)
        expect { described_class.validate!(nil) }.to raise_error(described_class::InvalidSqlError)
      end

      it "rejects non-SELECT/WITH statements" do
        expect { described_class.validate!("EXPLAIN SELECT * FROM repositories") }
          .to raise_error(described_class::InvalidSqlError)
        expect { described_class.validate!("SHOW tables") }
          .to raise_error(described_class::InvalidSqlError)
      end

      it "is case-insensitive on keywords" do
        expect { described_class.validate!("select 1; drop table users") }
          .to raise_error(described_class::InvalidSqlError)
        expect { described_class.validate!("SeLeCt * fRoM UsErS") }
          .to raise_error(described_class::InvalidSqlError)
      end
    end
  end

  describe ".strip_comments" do
    it "removes line comments" do
      expect(described_class.strip_comments("SELECT 1 -- bad\nFROM x")).not_to include("bad")
    end

    it "removes block comments (including multi-line)" do
      expect(described_class.strip_comments("SELECT /* line1\nline2 */ 1")).not_to include("line1")
    end
  end

  describe ".split_statements" do
    it "splits on top-level semicolons" do
      expect(described_class.split_statements("SELECT 1; SELECT 2")).to eq(["SELECT 1", "SELECT 2"])
    end

    it "preserves semicolons inside single-quoted strings" do
      expect(described_class.split_statements("SELECT ';'").length).to eq(1)
    end

    it "preserves semicolons inside double-quoted identifiers" do
      expect(described_class.split_statements(%Q(SELECT "a;b")).length).to eq(1)
    end

    it "ignores trailing empty statements" do
      expect(described_class.split_statements("SELECT 1;")).to eq(["SELECT 1"])
    end
  end
end
