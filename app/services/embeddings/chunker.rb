module Embeddings
  # Splits source files into overlapping, token-bounded chunks suitable for
  # embedding. We chunk by LINES with a token budget (not character count),
  # because embedding models have token — not byte — limits, and because
  # chunking on syntactic boundaries (blank lines, closing braces) preserves
  # far more semantic signal than fixed-size windows.
  class Chunker
    DEFAULT_MAX_TOKENS = 500   # well under text-embedding-3-small's 8191-token limit
    DEFAULT_OVERLAP    = 1     # one line of overlap between adjacent chunks

    Chunk = Struct.new(:content, :start_line, :end_line, :token_count, keyword_init: true)

    def initialize(max_tokens: DEFAULT_MAX_TOKENS, overlap_lines: DEFAULT_OVERLAP)
      @max_tokens    = max_tokens
      @overlap_lines = overlap_lines
    end

    # Accepts the full source of a file and returns an Array<Chunk>.
    def chunk(source)
      lines  = source.to_s.lines
      return [] if lines.empty?

      chunks       = []
      current      = []
      current_toks = 0
      start_line   = 1

      lines.each_with_index do |line, idx|
        line_toks = AI::Client.token_count(line)

        # If adding this line would overflow the budget AND we already have
        # content, flush the current chunk before starting a new one.
        if current_toks + line_toks > @max_tokens && current.any?
          end_line = start_line + current.length - 1
          chunks << Chunk.new(
            content:     current.join,
            start_line:  start_line,
            end_line:    end_line,
            token_count: current_toks
          )

          # Carry `overlap_lines` trailing lines into the next chunk for context.
          overlap      = current.last(@overlap_lines)
          current      = overlap.dup
          current_toks = overlap.sum { |l| AI::Client.token_count(l) }
          start_line   = end_line - overlap.length + 1
        end

        current      << line
        current_toks += line_toks
      end

      if current.any?
        chunks << Chunk.new(
          content:     current.join,
          start_line:  start_line,
          end_line:    start_line + current.length - 1,
          token_count: current_toks
        )
      end

      chunks
    end
  end
end
