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

      ended_session = nil
      StreamSession.transaction do
        session = StreamSession.lock.find(@stream_session.id)
        raise AlreadyEnded if session.ended_at.present?

        booth = Booth.lock.find(session.booth_id)

        # boothをoffline化 + current_stream_session_id解除
        booth.update!(
          status: :offline,
          current_stream_session_id: nil
        )

        DrinkOrders::RefundService.new(stream_session: session).call!

        session.update!(ended_at: Time.current, status: :ended)

        ended_session = session
      end
      StreamSessionNotifier.broadcast_ended(ended_session)
      ended_session
    end

    private

    def authorize!
      allowed = @actor.cast? || @actor.system_admin?
      raise NotAuthorized unless allowed
    end
  end
end
