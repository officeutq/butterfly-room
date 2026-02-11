# frozen_string_literal: true

class StreamSessionsController < ApplicationController
  include StoreBanGuard

  before_action :authenticate_user!
  before_action :set_stream_session
  before_action :reject_banned_customer_for_stream_session!

  def presence_summary
    viewer_count =
      begin
        Presences::SummaryService.new(
          stream_session: @stream_session,
          threshold_seconds: 45
        ).call!
      rescue => e
        Rails.logger.warn("[presence_summary] viewer_count failed: #{e.class} #{e.message}")
        0
      end

    joinable =
      begin
        Ivs::CreateParticipantTokenService.new(
          stream_session: @stream_session,
          actor: current_user,
          role: Ivs::CreateParticipantTokenService::ROLE_VIEWER
        ).joinable?
      rescue => e
        Rails.logger.warn("[presence_summary] joinable failed: #{e.class} #{e.message}")
        false
      end

    render json: { viewer_count: viewer_count, joinable: joinable }
  end

  private

  def set_stream_session
    @stream_session = StreamSession.find(params[:id])
  end

  def reject_banned_customer_for_stream_session!
    reject_banned_customer!(store: @stream_session.store)
  end
end
