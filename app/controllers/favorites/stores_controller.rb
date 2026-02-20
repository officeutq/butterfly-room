# frozen_string_literal: true

module Favorites
  class StoresController < ApplicationController
    before_action -> { require_at_least!(:customer) }
    before_action :set_store

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
          streams = [
            turbo_stream.replace(
              "store_favorite_button",
              partial: "favorites/stores/button",
              formats: [ :html ],
              locals: { store: @store, favorited: favorited }
            ),
            turbo_stream.replace(
              "store_#{@store.id}_favorite_button",
              partial: "favorites/stores/button",
              formats: [ :html ],
              locals: { store: @store, favorited: favorited }
            )
          ]
          render turbo_stream: streams
        end

        format.html { redirect_back fallback_location: store_path(@store) }
      end
    end
  end
end
