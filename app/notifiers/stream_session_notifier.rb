# frozen_string_literal: true

class StreamSessionNotifier
  def self.broadcast_stream_state(booth:)
    booth = Booth.find(booth.id)
    Turbo::StreamsChannel.broadcast_replace_to(
      [ booth, :stream_state ],
      target: "stream_state",
      partial: "booths/stream_state",
      locals: {
        booth: booth,
        stream_session: booth.current_stream_session,
        comments: booth.current_stream_session ? Comment.alive.where(stream_session: booth.current_stream_session)
                                               .order(created_at: :desc).limit(50).reverse : []
      }
    )
  end

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

    # viewer 側の映像領域を「終了表示」に差し替え（黒画面防止）
    Turbo::StreamsChannel.broadcast_replace_to(
      [ stream_session, :viewer_stage ],
      target: "viewer_stage",
      partial: "stream_sessions/viewer_ended",
      locals: { stream_session: stream_session }
    )
  end
end
