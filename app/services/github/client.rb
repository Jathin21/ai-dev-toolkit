module Github
  # Thin wrapper around Octokit that knows about our domain objects.
  # Every method returns plain Ruby data (hashes / arrays), never Octokit resources —
  # so that the rest of the app never depends on Octokit internals.
  class Client
    class Error < StandardError; end
    class NotFoundError < Error; end
    class AuthError < Error; end

    DEFAULT_PER_PAGE = 100

    def initialize(token: ENV["GITHUB_TOKEN"])
      raise AuthError, "GitHub token not configured" if token.blank?

      @client = Octokit::Client.new(access_token: token, per_page: DEFAULT_PER_PAGE)
      @client.auto_paginate = false  # we paginate explicitly to bound memory
    end

    def repo_metadata(full_name)
      data = @client.repository(full_name)
      {
        github_id:       data.id,
        full_name:       data.full_name,
        name:            data.name,
        owner:           data.owner.login,
        default_branch:  data.default_branch,
        clone_url:       data.clone_url
      }
    rescue Octokit::NotFound => e
      raise NotFoundError, "Repository not found: #{full_name} (#{e.message})"
    rescue Octokit::Unauthorized => e
      raise AuthError, e.message
    end

    # Yields each pull request hash. Uses explicit pagination so callers can
    # safely process tens of thousands of PRs without blowing up memory.
    def each_pull_request(full_name, state: "all", since: nil)
      return enum_for(:each_pull_request, full_name, state: state, since: since) unless block_given?

      page = 1
      loop do
        batch = @client.pull_requests(full_name, state: state, page: page, sort: "updated", direction: "desc")
        break if batch.empty?

        batch.each do |pr|
          next if since && pr.updated_at && pr.updated_at < since

          yield pr_to_hash(pr)
        end

        break if since && batch.last.updated_at && batch.last.updated_at < since
        break if batch.size < DEFAULT_PER_PAGE

        page += 1
      end
    end

    # Returns the unified diff for a PR, capped at `max_bytes` to protect the
    # context window. GitHub serves diffs directly when you set the right Accept header.
    def pull_request_diff(full_name, number, max_bytes: 120_000)
      diff = @client.pull_request(full_name, number, accept: "application/vnd.github.v3.diff")
      diff.to_s.byteslice(0, max_bytes)
    rescue Octokit::NotFound => e
      raise NotFoundError, e.message
    end

    # Yields (file_path, content) for every blob in the repo's default branch
    # that matches our language/size filters. Uses the Git Trees API with
    # recursive=true for efficiency.
    def each_source_file(full_name, branch: nil, max_bytes_per_file: 200_000)
      return enum_for(:each_source_file, full_name, branch: branch, max_bytes_per_file: max_bytes_per_file) unless block_given?

      repo    = @client.repository(full_name)
      branch ||= repo.default_branch
      sha     = @client.branch(full_name, branch).commit.sha
      tree    = @client.tree(full_name, sha, recursive: true)

      tree.tree.each do |entry|
        next unless entry.type == "blob"
        next unless SourceFileFilter.indexable?(entry.path)
        next if entry.respond_to?(:size) && entry.size.to_i > max_bytes_per_file

        blob = @client.blob(full_name, entry.sha)
        content = blob.encoding == "base64" ? Base64.decode64(blob.content) : blob.content.to_s

        # Silently skip binary blobs that slipped past the extension filter.
        next if content.encoding == Encoding::ASCII_8BIT && !content.force_encoding("UTF-8").valid_encoding?

        yield(entry.path, content, sha)
      end
    end

    private

    def pr_to_hash(pr)
      {
        github_id:     pr.id,
        number:        pr.number,
        title:         pr.title,
        body:          pr.body,
        state:         pr.merged_at ? "merged" : pr.state,
        author_login:  pr.user&.login,
        base_ref:      pr.base&.ref,
        head_ref:      pr.head&.ref,
        head_sha:      pr.head&.sha,
        additions:     pr.additions,
        deletions:     pr.deletions,
        changed_files: pr.changed_files,
        pr_created_at: pr.created_at,
        pr_updated_at: pr.updated_at,
        pr_merged_at:  pr.merged_at
      }
    end
  end
end
