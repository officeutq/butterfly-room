# frozen_string_literal: true

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  devise_for :users, skip: %i[registrations]

  root "home#show"

  if Rails.env.development?
    namespace :dev do
      resource :banuba_verification, only: %i[show], controller: "banuba_verifications"
      resource :deepar_verification, only: %i[show], controller: "deepar_verifications"
      resource :filepond_verification, only: %i[show create], controller: "filepond_verifications"
    end
  end

  # --- Common dashboard (login required) ---
  get "/dashboard", to: "dashboard#show", as: :dashboard

  # --- Common profile (login required) ---
  resource :profile, only: %i[edit update]

  # --- Phone verification (login required) ---
  resource :phone_verification, only: [] do
    get :new
    post :create
    get :confirm
    post :verify
  end

  # --- Phone session (guest login) ---
  resource :phone_session, only: [] do
    get :new
    post :create
    get :confirm
    post :verify
  end

  # --- Public user profiles (login required) ---
  resources :users, only: %i[show] do
    resource :favorite, only: %i[create destroy], controller: "favorites/users"
  end

  # --- Public (customer registration) ---
  get  "/sign_up", to: "customers/registrations#new", as: :sign_up
  post "/sign_up", to: "customers/registrations#create"

  # --- Cast registration (invite only) ---
  get  "/cast/sign_up", to: "casts/registrations#new", as: :cast_sign_up
  post "/cast/sign_up", to: "casts/registrations#create"

  # --- StoreAdmin registration (invite only) ---
  get  "/store_admin/sign_up", to: "store_admins/registrations#new", as: :store_admin_sign_up
  post "/store_admin/sign_up", to: "store_admins/registrations#create"

  # --- Public (store registration) ---
  namespace :stores do
    get  :new_registration, to: "registrations#new"
    post :registrations, to: "registrations#create"
  end

  # --- Public (cast invitation) ---
  get  "/cast_invitations/:token", to: "cast_invitations#show", as: :cast_invitation
  post "/cast_invitations/:token/accept", to: "cast_invitations#accept", as: :accept_cast_invitation

  # --- Public (store_admin invitation) ---
  get  "/store_admin_invitations/:token", to: "store_admin_invitations#show", as: :store_admin_invitation
  post "/store_admin_invitations/:token/accept", to: "store_admin_invitations#accept", as: :accept_store_admin_invitation

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
      get :viewer_drink_menu
    end

    resource :favorite, only: %i[create destroy], controller: "favorites/booths"
  end

  resources :stream_sessions, only: [] do
    resources :comments, only: %i[create], module: :stream_sessions do
      member do
        patch :hide
        patch :unhide
        post :report
      end
    end

    resources :drink_orders, only: %i[create], module: :stream_sessions
    resources :ivs_participant_tokens, only: %i[create], module: :stream_sessions

    resource :presence, only: [], module: :stream_sessions do
      post :ping
    end

    get :presence_summary, on: :member
  end

  namespace :wallet do
    resources :purchases, only: %i[new create]
  end

  get  "/checkout/return", to: "checkout#return"
  post "/webhooks/stripe", to: "webhooks/stripe#create"

  # --- Cast ---
  namespace :cast do
    resource :current_booth, only: %i[create]

    resources :booths, only: %i[index edit update] do
      collection do
        get :select_modal
      end

      get :live, on: :member
      patch :status, on: :member
      resources :stream_sessions, only: %i[create], module: :booths
    end

    resources :stream_sessions, only: %i[show] do
      post :finish, on: :member
      get  :pending_drink_orders, on: :member
      get  :meta_display, on: :member
      patch :metadata, on: :member
      patch :start_broadcast, on: :member
    end

    resources :drink_orders, only: [] do
      post :consume, on: :member
    end
  end

  # --- Store Admin ---
  namespace :admin do
    resources :stores, only: %i[index edit update] do
      collection do
        get :select_modal
      end
    end

    resource :payout_account, only: %i[edit update], controller: "store_payout_accounts"
    resource :current_store, only: %i[create], controller: "current_stores"

    resource :onboarding, only: [] do
      post :skip
      post :cast_invitation_copied
    end

    resources :booths, only: %i[index new create] do
      member do
        patch :archive
        post :force_end
        post :assign_cast
      end
    end

    resources :drink_items, only: %i[index create update destroy]
    resources :store_bans, only: %i[index create destroy]
    resources :comment_reports, only: %i[index] do
      post :reject, on: :member
      post :ban, on: :member
    end

    resources :casts, only: %i[index destroy]
    resources :cast_invitations, only: %i[index create]
    resources :store_admin_invitations, only: %i[index create]

    get "/cast_metrics", to: "metrics#cast"

    resources :settlements, only: %i[index show]
  end

  # --- System Admin ---
  namespace :system_admin do
    resources :referral_codes, only: %i[index new create edit update]
    resources :users, only: %i[index new create edit update destroy]
    resources :effects, only: %i[index new create edit update]

    resources :settlements, only: %i[index show] do
      collection do
        get  "manual/new", to: "settlements#new_manual", as: :new_manual
        post "manual/preview", to: "settlements#preview_manual", as: :preview_manual
        post "manual", to: "settlements#create_manual", as: :create_manual

        post :export_csv
      end

      member do
        post :confirm
        post :mark_paid
      end
    end

    resources :settlement_exports, only: %i[index show create]
  end
end
