FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    name     { "Test User" }
    password { "password1234" }
    role     { "member" }

    trait(:admin) { role { "admin" } }
  end

  factory :repository do
    user
    sequence(:full_name) { |n| "owner#{n}/repo#{n}" }
    owner           { full_name.split("/").first }
    name            { full_name.split("/").last }
    default_branch  { "main" }
    indexing_status { "completed" }
    github_id       { rand(1_000_000) }
    last_synced_at  { 1.hour.ago }
    last_indexed_at { 1.hour.ago }
  end

  factory :pull_request do
    repository
    sequence(:number)    { |n| n }
    sequence(:github_id) { |n| 1_000_000 + n }
    title        { "Fix the thing" }
    state        { "open" }
    author_login { "alice" }
    ai_status    { "pending" }
  end

  factory :code_embedding do
    repository
    file_path      { "app/models/user.rb" }
    language       { "ruby" }
    commit_sha     { SecureRandom.hex(20) }
    chunk_index    { 0 }
    start_line     { 1 }
    end_line       { 10 }
    content        { "class User\nend" }
    content_digest { CodeEmbedding.digest_for(content) }
    embedding      { Array.new(1536) { rand(-1.0..1.0) } }
    token_count    { 10 }
  end

  factory :query do
    user
    question { "how many PRs were merged last week?" }
    status   { "pending" }
  end
end
