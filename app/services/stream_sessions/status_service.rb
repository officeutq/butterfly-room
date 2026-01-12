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

        unless %i[live away].include?(booth.status.to_sym)
          raise InvalidTransition, "booth is #{booth.status}"
        end

        unless %i[live away].include?(@to_status)
          raise InvalidTransition, "to_status must be live or away"
        end

        # live -> away / away -> live のみ許可（同じ状態への更新は許容しても良い）
        if booth.status.to_sym == :live && @to_status == :away
          booth.update!(status: :away)
        elsif booth.status.to_sym == :away && @to_status == :live
          booth.update!(status: :live)
        elsif booth.status.to_sym == @to_status
          # no-op（好みでOK/NG）
        else
          raise InvalidTransition, "from #{booth.status} to #{@to_status}"
        end

        booth
      end
    end

    private

    def authorize!
      allowed = @actor.cast? || @actor.system_admin?
      raise NotAuthorized unless allowed
    end
  end
end
