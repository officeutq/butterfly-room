# frozen_string_literal: true

class BoothsController < ApplicationController
  def show
    @booth = Booth.find(params[:id])
    @stream_session = @booth.current_stream_session
    @drink_items = @booth.store.drink_items.enabled_only.ordered

    @wallet =
      if user_signed_in?
        Wallet.find_or_create_by!(customer_user_id: current_user.id) do |w|
          w.available_points = 0
          w.reserved_points = 0
        end
      end

    @comments =
      if @stream_session.present?
        Comment.alive.where(stream_session: @stream_session)
              .order(created_at: :desc)
              .limit(50)
              .reverse
      else
        []
      end
  end
end
