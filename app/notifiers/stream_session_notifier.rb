# frozen_string_literal: true

class StreamSessionNotifier
  def self.broadcast_ended(stream_session)
    Turbo::StreamsChannel.broadcast_replace_to(
      [ stream_session, :pending_drink_orders ],
      target: "pending_drink_orders",
      partial: "stream_sessions/ended",
      locals: { stream_session: stream_session }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      [ stream_session, :cast_pending_drink_orders ],
      target: "cast_pending_drink_orders",
      partial: "cast/stream_sessions/ended",
      locals: { stream_session: stream_session }
    )
  end
end
