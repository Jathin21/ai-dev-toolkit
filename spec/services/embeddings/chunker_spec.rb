require "rails_helper"

RSpec.describe Embeddings::Chunker do
  let(:chunker) { described_class.new(max_tokens: 50, overlap_lines: 1) }

  it "returns an empty array for empty input" do
    expect(chunker.chunk("")).to eq([])
    expect(chunker.chunk(nil)).to eq([])
  end

  it "returns one chunk for small input" do
    chunks = chunker.chunk("def foo\n  1\nend\n")
    expect(chunks.length).to eq(1)
    expect(chunks.first.start_line).to eq(1)
    expect(chunks.first.end_line).to   eq(3)
  end

  it "splits input that exceeds the token budget" do
    source  = Array.new(200) { |i| "line_#{i} = #{'x' * 20}\n" }.join
    chunks  = chunker.chunk(source)

    expect(chunks.length).to be > 1
    chunks.each { |c| expect(c.token_count).to be <= 60 } # small slack above budget
  end

  it "produces contiguous line ranges with the configured overlap" do
    source = Array.new(120) { |i| "l#{i}\n" }.join
    chunks = chunker.chunk(source)

    chunks.each_cons(2) do |a, b|
      # overlap_lines: 1 means the next chunk's start_line is the prior chunk's end_line
      expect(b.start_line).to eq(a.end_line)
    end
  end
end
