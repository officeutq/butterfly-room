# frozen_string_literal: true

class StreamSessionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_stream_session

  def presence_summary
    viewer_count = Presences::SummaryService.new(
      stream_session: @stream_session,
      threshold_seconds: 45
    ).call!

    render json: { viewer_count: viewer_count }
  end

  private

  def set_stream_session
    @stream_session = StreamSession.find(params[:id])
  end
end
