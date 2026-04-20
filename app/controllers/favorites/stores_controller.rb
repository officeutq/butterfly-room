# frozen_string_literal: true

module Favorites
  class StoresController < ApplicationController
    before_action -> { require_at_least!(:customer) }
    before_action :set_store, only: %i[create destroy]

    def index
      scope =
        current_user
          .favorite_stores
          .joins(:store)
          .includes(:store)
          .order(created_at: :desc, id: :desc)

      # customer のみ BAN store を除外（Home と同じ思想）
      if current_user.customer?
        banned_store_ids = StoreBan.where(customer_user_id: current_user.id).select(:store_id)
        scope = scope.where.not(stores: { id: banned_store_ids })
      end

      @favorite_stores = scope
    end

    def create
      current_user.favorite_stores.find_or_create_by!(store: @store)

      render_favorite_button(favorited: true)
    rescue ActiveRecord::RecordNotUnique
      render_favorite_button(favorited: true)
    end

    def destroy
      current_user.favorite_stores.where(store: @store).destroy_all

      render_favorite_button(favorited: false)
    end

    private

    def set_store
      @store = Store.find(params[:store_id])
    end

    def render_favorite_button(favorited:)
      respond_to do |format|
        format.turbo_stream do
          home_dom_id = params[:dom_id].presence || "store_#{@store.id}_favorite_button"

          streams = [
            turbo_stream.replace(
              "store_favorite_button",
              partial: "favorites/stores/button_store_show",
              formats: [ :html ],
              locals: { store: @store, favorited: favorited }
            ),
            turbo_stream.replace(
              home_dom_id,
              partial: "favorites/stores/button_home",
              formats: [ :html ],
              locals: { store: @store, favorited: favorited, dom_id: home_dom_id }
            )
          ]
          render turbo_stream: streams
        end

        format.html { redirect_back fallback_location: store_path(@store) }
      end
    end
  end
end
