# frozen_string_literal: true

module StreamSessions
  class StatusService
    class Error < StandardError; end
    class NotAuthorized < Error; end
    class NoCurrentSession < Error; end
    class InvalidTransition < Error; end
    class AnotherBoothAlreadyLive < Error; end

    def initialize(booth:, actor:, to_status:)
      @booth = booth
      @actor = actor
      @to_status = to_status.to_sym
    end

    def call
      authorize!

      Booth.transaction do
        booth = Booth.lock.find(@booth.id)

        raise NoCurrentSession if booth.current_stream_session_id.nil?
        raise InvalidTransition, "to_status must be live or away" unless %i[live away].include?(@to_status)

        from = booth.status.to_sym

        if @to_status == :live && another_live_booth_exists?(booth)
          raise AnotherBoothAlreadyLive, "他のブースで配信中のため開始できません"
        end

        now = Time.current

        # Issue #78 遷移
        # standby -> live（配信開始後にサーバ側でliveへ）
        # live <-> away
        # 同一はno-op
        case [ from, @to_status ]
        when %i[standby live]
          booth.update!(status: :live, last_online_at: now)
        when %i[live away]
          booth.update!(status: :away, last_online_at: now)
        when %i[away live]
          booth.update!(status: :live, last_online_at: now)
        when [ @to_status, @to_status ]
          # no-op
        else
          raise InvalidTransition, "from #{from} to #{@to_status}"
        end

        booth
      end
    end

    private

    def authorize!
      raise NotAuthorized unless @actor.at_least?(:cast)
    end

    def another_live_booth_exists?(booth)
      Booth.active
           .joins(:current_stream_session)
           .where(stream_sessions: { started_by_cast_user_id: @actor.id })
           .where(status: %i[live away])
           .where.not(id: booth.id)
           .exists?
    end
  end
end
