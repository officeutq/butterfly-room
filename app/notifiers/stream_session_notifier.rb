# frozen_string_literal: true

class StreamSessionNotifier
  def self.broadcast_stream_state(booth:, flash_message: nil)
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
        drink_items: booth.store.drink_items.enabled_only.ordered,
        flash_message: flash_message
      }
    )
  end

  def self.broadcast_ended(stream_session)
    Turbo::StreamsChannel.broadcast_replace_to(
      [ stream_session, :cast_pending_drink_orders ],
      target: "cast_pending_drink_orders",
      partial: "cast/stream_sessions/ended",
      locals: { stream_session: stream_session }
    )

    Turbo::StreamsChannel.broadcast_append_to(
      [ stream_session.booth, :stream_state ],
      target: "flash_inner",
      partial: "shared/flash_message",
      locals: { level: "secondary", message: "配信が終了しました。未消化ドリンクは返却されました。" }
    )
  end
end
