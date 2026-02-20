# frozen_string_literal: true

module Favorites
  class BoothsController < ApplicationController
    before_action -> { require_at_least!(:customer) }
    before_action :set_booth

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
              partial: "favorites/booths/button",
              formats: [ :html ],
              locals: { booth: @booth, favorited: favorited }
            ),
            turbo_stream.replace(
              "booth_#{@booth.id}_favorite_button",
              partial: "favorites/booths/button",
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
