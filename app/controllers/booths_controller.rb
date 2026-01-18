# frozen_string_literal: true

class BoothsController < ApplicationController
  def show
    @booth = Booth.find(params[:id])
    @stream_session = @booth.current_stream_session
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
