# frozen_string_literal: true

class StreamSessionNotifier
  def self.broadcast_stream_state(booth:)
    booth = Booth.find(booth.id)
    stream_session = booth.current_stream_session

    Turbo::StreamsChannel.broadcast_update_to(
      [ booth, :stream_state ],
      target: "stream_state",
      partial: "booths/stream_state",
      locals: {
        booth: booth,
        stream_session: stream_session,
        comments: stream_session ? Comment.alive.where(stream_session: stream_session)
                                     .order(created_at: :desc).limit(50).reverse : [],
        drink_items: booth.store.drink_items.enabled_only.ordered
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

    Turbo::StreamsChannel.broadcast_replace_to(
      [ stream_session, :viewer_stage ],
      target: "viewer_stage",
      partial: "stream_sessions/viewer_ended",
      locals: { stream_session: stream_session }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      [ stream_session.booth, :stream_state ],
      target: "flash_inner",
      partial: "shared/flash_message",
      locals: { level: "secondary", message: "配信が終了しました。未消化ドリンクは返却されました。" }
    )
  end
end
