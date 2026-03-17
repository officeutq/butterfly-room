# frozen_string_literal: true

class StreamSessions::PresencesController < ApplicationController
  include StoreBanGuard

  before_action :authenticate_user!
  before_action :set_stream_session
  before_action :reject_banned_customer_for_stream_session!

  def ping
    policy = Authorization::ViewerPolicy.new(current_user, @stream_session)
    head :forbidden and return unless policy.ping_presence?

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

  def reject_banned_customer_for_stream_session!
    reject_banned_customer!(store: @stream_session.store)
  end
end
