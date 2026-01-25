Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  devise_for :users, skip: %i[registrations]

  root "home#show"

  # --- Public (customer) ---
  resources :booths, only: %i[show]

  resources :stream_sessions, only: [] do
    resources :comments, only: %i[create], module: :stream_sessions
    resources :drink_orders, only: %i[create], module: :stream_sessions

    resource :presence, only: [], module: :stream_sessions do
      post :ping
    end

    get :presence_summary, on: :member
  end

  namespace :wallet do
    resources :purchases, only: %i[create]
  end

  get  "/checkout/return", to: "checkout#return"
  post "/webhooks/stripe", to: "webhooks/stripe#create"

  # --- Cast ---
  namespace :cast do
    resources :booths, only: %i[index show] do
      patch :status, on: :member
      resources :stream_sessions, only: %i[create], module: :booths
    end

    resources :stream_sessions, only: [] do
      post :finish, on: :member
      get  :pending_drink_orders, on: :member
    end

    resources :drink_orders, only: [] do
      post :consume, on: :member
    end
  end

  # --- Store Admin ---
  namespace :admin do
    root "dashboard#show"

    resource :store, only: %i[show update]
    resources :booths, only: %i[index create update]
    resources :drink_items, only: %i[index create update destroy]
    resources :store_bans, only: %i[index create destroy]
    resources :casts, only: %i[index create destroy]
    get "/cast_metrics", to: "metrics#cast"
  end
end
