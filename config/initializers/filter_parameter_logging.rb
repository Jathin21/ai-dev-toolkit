Rails.application.config.filter_parameters += %i[
  password
  password_confirmation
  secret
  token
  api_key
  access_token
  openai_api_key
  github_token
]
