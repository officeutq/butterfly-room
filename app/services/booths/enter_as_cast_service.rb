# frozen_string_literal: true

module Booths
  class EnterAsCastService
    class Error < StandardError; end
    class NotAuthorized < Error; end

    Result = Struct.new(:action, :booth, :stream_session, keyword_init: true)

    def initialize(booth:, actor:)
      @booth = booth
      @actor = actor
    end

    def call
      authorize!

      Booth.transaction do
        booth = Booth.lock.find(@booth.id)
        raise ActiveRecord::RecordNotFound if booth.archived?

        current_stream_session = booth.current_stream_session

        if booth.offline?
          return handle_offline!(booth, current_stream_session)
        end

        if booth.standby?
          return handle_standby!(booth, current_stream_session)
        end

        if booth.live? || booth.away?
          return handle_live_or_away(booth, current_stream_session)
        end

        Result.new(action: :occupied_by_other, booth: booth, stream_session: current_stream_session)
      end
    end

    private

    def authorize!
      actor = @actor
      booth = @booth

      allowed =
        if actor.blank?
          false
        elsif actor.system_admin?
          true
        elsif actor.at_least?(:store_admin)
          actor.admin_of_store?(booth.store_id)
        else
          BoothCast.exists?(cast_user_id: actor.id, booth_id: booth.id)
        end

      raise NotAuthorized, "選択できないブースです" unless allowed
    end

    def handle_offline!(booth, current_stream_session)
      if booth.current_stream_session_id.present?
        if current_stream_session.present?
          booth.update!(status: :standby)
          return Result.new(action: :redirect_live, booth: booth, stream_session: current_stream_session)
        end

        booth.update!(current_stream_session_id: nil)
      end

      stream_session = StreamSessions::StartService.new(booth: booth, actor: @actor).call
      Result.new(action: :redirect_live, booth: booth.reload, stream_session: stream_session)
    end

    def handle_standby!(booth, current_stream_session)
      if current_stream_session.present?
        return Result.new(action: :redirect_live, booth: booth, stream_session: current_stream_session)
      end

      booth.update!(status: :offline, current_stream_session_id: nil)

      stream_session = StreamSessions::StartService.new(booth: booth, actor: @actor).call
      Result.new(action: :redirect_live, booth: booth.reload, stream_session: stream_session)
    end

    def handle_live_or_away(booth, current_stream_session)
      if current_stream_session.present? && current_stream_session.started_by_cast_user_id == @actor.id
        return Result.new(action: :redirect_live, booth: booth, stream_session: current_stream_session)
      end

      Result.new(action: :occupied_by_other, booth: booth, stream_session: current_stream_session)
    end
  end
end
