# frozen_string_literal: true

module StreamSessions
  class StartService
    class Error < StandardError; end
    class BoothNotOffline < Error; end
    class NotAuthorized < Error; end

    def initialize(booth:, actor:)
      @booth = booth
      @actor = actor
    end

    def call
      authorize!

      StreamSession.transaction do
        booth = Booth.lock.find(@booth.id)

        raise BoothNotOffline, "booth is #{booth.status}" unless booth.offline?

        session = StreamSession.create!(
          booth: booth,
          store: booth.store,
          status: :live,
          started_at: Time.current,
          started_by_cast_user: @actor
        )

        booth.update!(
          status: :live,
          current_stream_session_id: session.id
        )

        session
      end
    end

    private

    def authorize!
      # 最小：cast/system_adminのみ
      # 追加：そのブースに所属しているか（booth_casts等）をここで担保
      allowed = @actor.cast? || @actor.system_admin?
      raise NotAuthorized unless allowed
    end
  end
end
