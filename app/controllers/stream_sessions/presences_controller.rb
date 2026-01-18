# frozen_string_literal: true

class StreamSessions::PresencesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_stream_session
  # before_action :require_customer! # 必要なら有効化

  def ping
    Presences::PingService.new(
      stream_session: @stream_session,
      customer_user: current_user
    ).call!

    head :no_content
  end

  private

  def set_stream_session
    @stream_session = StreamSession.find(params[:stream_session_id])
  end

  # def require_customer!
  #   return if current_user.customer?
  #   render json: { error: "forbidden" }, status: :forbidden
  # end
end
