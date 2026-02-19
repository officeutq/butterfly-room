# frozen_string_literal: true

module StreamSessions
  class StatusService
    class Error < StandardError; end
    class NotAuthorized < Error; end
    class NoCurrentSession < Error; end
    class InvalidTransition < Error; end

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

        # Issue #78 遷移
        # standby -> live（配信開始後にサーバ側でliveへ）
        # live <-> away
        # 同一はno-op
        case [ from, @to_status ]
        when %i[standby live]
          booth.update!(status: :live)
        when %i[live away]
          booth.update!(status: :away)
        when %i[away live]
          booth.update!(status: :live)
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
  end
end
