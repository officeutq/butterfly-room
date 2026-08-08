# frozen_string_literal: true

module Booths
  class CloseAndArchiveService
    class Error < StandardError; end
    class InconsistentState < Error; end

    Result = Struct.new(:booth, :archived, keyword_init: true)

    def initialize(booth:, actor:)
      @booth = booth
      @actor = actor
    end

    def call!
      booth = Booth.find(@booth.id)
      return Result.new(booth:, archived: false) if booth.archived?

      end_stream_session_if_needed!(booth)

      archived = false

      Booth.transaction do
        booth = Booth.lock.find(booth.id)
        next if booth.archived?

        unless booth.offline? && booth.current_stream_session_id.nil?
          raise InconsistentState, "ブース##{booth.id}の配信状態が整っていないためアーカイブできません"
        end

        booth.update!(archived_at: Time.current)
        archived = true
      end

      Result.new(booth: booth.reload, archived:)
    end

    private

    def end_stream_session_if_needed!(booth)
      booth.reload

      case booth.status.to_sym
      when :offline
        if booth.current_stream_session_id.present?
          raise InconsistentState, "ブース##{booth.id}に終了していない配信情報が残っています"
        end
      when :standby, :live, :away
        stream_session = StreamSession.find_by(id: booth.current_stream_session_id)
        if stream_session.blank?
          raise InconsistentState, "ブース##{booth.id}の配信セッションが見つかりません"
        end

        StreamSessions::ForceEndService.new(
          stream_session:,
          actor: @actor
        ).call
      else
        raise InconsistentState, "ブース##{booth.id}の状態を判定できません"
      end
    end
  end
end
