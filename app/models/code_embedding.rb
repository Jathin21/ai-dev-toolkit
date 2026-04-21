class CodeEmbedding < ApplicationRecord
  # The `neighbor` gem provides `has_neighbors`, which wires up
  # `.nearest_neighbors(:embedding, vector, distance: :cosine)` as a scope.
  has_neighbors :embedding

  belongs_to :repository

  validates :file_path,      presence: true
  validates :content,        presence: true
  validates :content_digest, presence: true
  validates :commit_sha,     presence: true
  validates :embedding,      presence: true
  validates :chunk_index,    presence: true,
                             uniqueness: { scope: %i[repository_id file_path] }

  # Convenience: compute a stable digest for a piece of content.
  def self.digest_for(text)
    Digest::SHA256.hexdigest(text)
  end

  # Returns a short preview suitable for search-result cards.
  def preview(limit: 240)
    content.to_s.truncate(limit, separator: "\n")
  end

  def location_label
    "#{file_path}:#{start_line}-#{end_line}"
  end
end
