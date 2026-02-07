# frozen_string_literal: true

module StreamSessions
  class StartService
    class Error < StandardError; end
    class BoothNotOffline < Error; end
    class NotAuthorized < Error; end
    class BoothStageNotBound < Error; end

    def initialize(booth:, actor:)
      @booth = booth
      @actor = actor
    end

    def call
      authorize!

      StreamSession.transaction do
        booth = Booth.lock.find(@booth.id)

        raise BoothNotOffline, "booth is #{booth.status}" unless booth.offline?

        raise BoothStageNotBound, "booth.ivs_stage_arn is blank" if booth.ivs_stage_arn.blank?

        session = StreamSession.create!(
          booth: booth,
          store: booth.store,
          status: :live, # ※ここは現状維持でもOK（後で整理してもよい）
          started_at: Time.current,
          started_by_cast_user: @actor,
          ivs_stage_arn: booth.ivs_stage_arn # ★ここが #123
        )

        booth.update!(
          status: :standby,
          current_stream_session_id: session.id
        )

        session
      end
    end

    private

    def authorize!
      policy = Authorization::BoothPolicy.new(@actor, @booth)
      allowed = policy.cast_operate? # これがあるなら
      raise NotAuthorized unless allowed
    end
  end
end
