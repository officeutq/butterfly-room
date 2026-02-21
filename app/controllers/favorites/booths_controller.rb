# frozen_string_literal: true

module Favorites
  class BoothsController < ApplicationController
    before_action -> { require_at_least!(:customer) }
    before_action :set_booth, only: %i[create destroy]

    def index
      scope =
        current_user
          .favorite_booths
          .joins(:booth)
          .merge(Booth.active)
          .includes(booth: :store)
          .order(created_at: :desc, id: :desc)

      # Home と同じ「可能な範囲で予防」：customer のみ BAN store を除外
      if current_user.customer?
        banned_store_ids = StoreBan.where(customer_user_id: current_user.id).select(:store_id)
        scope = scope.where.not(booths: { store_id: banned_store_ids })
      end

      @favorite_booths = scope
    end

    def create
      current_user.favorite_booths.find_or_create_by!(booth: @booth)

      render_favorite_button(favorited: true)
    rescue ActiveRecord::RecordNotUnique
      # UNIQUE index で競合しても成功扱いに寄せる
      render_favorite_button(favorited: true)
    end

    def destroy
      current_user.favorite_booths.where(booth: @booth).destroy_all

      render_favorite_button(favorited: false)
    end

    private

    def set_booth
      @booth = Booth.active.find(params[:booth_id])
    end

    def render_favorite_button(favorited:)
      respond_to do |format|
        format.turbo_stream do
          streams = [
            turbo_stream.replace(
              "booth_favorite_button",
              partial: "favorites/booths/button_booth_show",
              formats: [ :html ],
              locals: { booth: @booth, favorited: favorited }
            ),
            turbo_stream.replace(
              "booth_#{@booth.id}_favorite_button",
              partial: "favorites/booths/button_home",
              formats: [ :html ],
              locals: { booth: @booth, favorited: favorited }
            )
          ]
          render turbo_stream: streams
        end

        format.html { redirect_back fallback_location: booth_path(@booth) }
      end
    end
  end
end
