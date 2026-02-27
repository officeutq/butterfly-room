Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  devise_for :users, skip: %i[registrations]

  root "home#show"

  # --- Common dashboard (login required) ---
  get "/dashboard", to: "dashboard#show", as: :dashboard

  # --- Common profile (login required) ---
  resource :profile, only: %i[edit update]

  # --- Public user profiles (login required) ---
  resources :users, only: %i[show]

  # --- Public (customer registration) ---
  get  "/sign_up", to: "customers/registrations#new",    as: :sign_up
  post "/sign_up", to: "customers/registrations#create"

  # --- Cast registration (invite only) ---
  get  "/cast/sign_up", to: "casts/registrations#new",    as: :cast_sign_up
  post "/cast/sign_up", to: "casts/registrations#create"

  # --- Public (store registration) ---
  namespace :stores do
    get  :new_registration, to: "registrations#new"
    post :registrations,    to: "registrations#create"
  end

  # --- Public (cast invitation) ---
  get  "/cast_invitations/:token", to: "cast_invitations#show",   as: :cast_invitation
  post "/cast_invitations/:token/accept", to: "cast_invitations#accept", as: :accept_cast_invitation

  # --- Favorites (login required) ---
  namespace :favorites do
    resources :booths, only: %i[index]
    resources :stores, only: %i[index]
  end

  # --- Customer (login required) ---
  resources :stores, only: %i[show] do
    resource :favorite, only: %i[create destroy], controller: "favorites/stores"
  end

  # --- Public (customer) ---
  resources :booths, only: %i[show] do
    member do
      get :enter
      post :enter_as_cast
    end

    resource :favorite, only: %i[create destroy], controller: "favorites/booths"
  end

  resources :stream_sessions, only: [] do
    resources :comments, only: %i[create], module: :stream_sessions
    resources :drink_orders, only: %i[create], module: :stream_sessions
    resources :ivs_participant_tokens, only: %i[create], module: :stream_sessions

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
    # current_booth selection
    resource :current_booth, only: %i[create]

    resources :booths, only: %i[index show edit update] do
      get :live, on: :member
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
    # current_store selection
    resources :stores, only: %i[index edit update]
    resource :current_store, only: %i[create], controller: "current_stores"

    resources :booths, only: %i[index show new edit create update] do
      member do
        get :watch
        patch :archive
        post :force_end
      end
    end

    resources :drink_items, only: %i[index create update destroy]
    resources :store_bans, only: %i[index create destroy]

    resources :casts, only: %i[index destroy] do
      collection do
        post :invite
      end
    end

    get "/cast_metrics", to: "metrics#cast"
  end

  # --- System Admin ---
  namespace :system_admin do
    resources :referral_codes, only: %i[index new create edit update]
    resources :users, only: %i[index new create edit update destroy]
  end
end
