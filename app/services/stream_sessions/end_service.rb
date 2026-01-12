# frozen_string_literal: true

module StreamSessions
  class EndService
    class Error < StandardError; end
    class NotAuthorized < Error; end
    class AlreadyEnded < Error; end

    def initialize(stream_session:, actor:)
      @stream_session = stream_session
      @actor = actor
    end

    def call
      authorize!

      StreamSession.transaction do
        session = StreamSession.lock.find(@stream_session.id)
        raise AlreadyEnded if session.ended_at.present?

        booth = Booth.lock.find(session.booth_id)

        # boothをoffline化 + current_stream_session_id解除
        booth.update!(
          status: :offline,
          current_stream_session_id: nil
        )

        # 返却Service呼び出し（Issue15では「接続だけ」）
        # 実体が未実装なら TODO のままでもOK（ただしPhase1の最終要件では必須）
        if defined?(DrinkOrders::RefundService)
          DrinkOrders::RefundService.new(stream_session: session).call
        end

        session.update!(ended_at: Time.current, status: :ended)

        session
      end
    end

    private

    def authorize!
      allowed = @actor.cast? || @actor.system_admin?
      raise NotAuthorized unless allowed
    end
  end
end
