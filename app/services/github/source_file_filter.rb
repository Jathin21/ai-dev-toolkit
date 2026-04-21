module Github
  # Decides whether a path is worth indexing. We deliberately skip lockfiles,
  # vendored dependencies, build artifacts, and media — they're noisy and
  # would dominate embedding-search results.
  module SourceFileFilter
    INDEXABLE_EXTENSIONS = %w[
      .rb .py .js .jsx .ts .tsx .go .rs .java .kt .swift .c .h .cpp .hpp .cs
      .php .scala .ex .exs .erl .clj .lua .sh .bash .zsh .fish
      .sql .graphql .proto .md .rst
      .yml .yaml .toml .json .xml
      .html .erb .haml .slim .vue .svelte .astro
      .css .scss .sass .less
    ].freeze

    SKIP_PATTERNS = [
      %r{\A(node_modules|vendor|dist|build|tmp|log|coverage)/},
      %r{\A\.(git|github|idea|vscode)/},
      %r{(\.min\.(js|css))\z},
      %r{\A(package-lock\.json|yarn\.lock|Gemfile\.lock|poetry\.lock|Cargo\.lock|pnpm-lock\.yaml)\z}
    ].freeze

    def self.indexable?(path)
      return false if SKIP_PATTERNS.any? { |rx| rx.match?(path) }

      ext = File.extname(path).downcase
      INDEXABLE_EXTENSIONS.include?(ext)
    end

    def self.language_for(path)
      case File.extname(path).downcase
      when ".rb"               then "ruby"
      when ".py"               then "python"
      when ".js", ".jsx"       then "javascript"
      when ".ts", ".tsx"       then "typescript"
      when ".go"               then "go"
      when ".rs"               then "rust"
      when ".java"             then "java"
      when ".kt"               then "kotlin"
      when ".swift"            then "swift"
      when ".c", ".h"          then "c"
      when ".cpp", ".hpp"      then "cpp"
      when ".cs"               then "csharp"
      when ".php"              then "php"
      when ".scala"            then "scala"
      when ".ex", ".exs"       then "elixir"
      when ".sql"              then "sql"
      when ".md"               then "markdown"
      when ".yml", ".yaml"     then "yaml"
      when ".json"             then "json"
      when ".html", ".erb"     then "html"
      when ".css", ".scss"     then "css"
      else                          "text"
      end
    end
  end
end
