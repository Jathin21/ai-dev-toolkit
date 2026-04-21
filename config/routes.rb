Rails.application.routes.draw do
  devise_for :users

  # Sidekiq web UI — gated behind authentication in production
  require "sidekiq/web"
  require "sidekiq/cron/web"
  authenticate :user, ->(u) { u.admin? } do
    mount Sidekiq::Web => "/sidekiq"
  end

  root "pages#dashboard"

  # Primary feature resources
  resources :repositories do
    member do
      post :sync
      post :reindex
    end

    resources :pull_requests, only: %i[index show] do
      member do
        post :summarize
      end
    end

    resources :code_searches, only: %i[index create]
    resources :queries,       only: %i[index create show]
  end

  # Health check endpoint for load balancers
  get "/up" => "rails/health#show", as: :rails_health_check

  # JSON API
  namespace :api do
    namespace :v1 do
      resources :repositories, only: %i[index show] do
        resources :pull_requests, only: %i[index show] do
          member { post :summarize }
        end
        resources :code_searches, only: %i[create]
        resources :queries,       only: %i[create]
      end
    end
  end
end
