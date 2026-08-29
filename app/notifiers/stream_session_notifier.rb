# frozen_string_literal: true

class StreamSessionNotifier
  def self.broadcast_stream_state(booth:)
    booth = Booth.find(booth.id)
    stream_session = booth.current_stream_session

    { authenticated: true, guest: false }.each do |variant, authenticated_viewer|
      Turbo::StreamsChannel.broadcast_update_to(
        [ booth, :stream_state, variant ],
        target: "stream_state",
        partial: "booths/stream_state",
        locals: {
          booth: booth,
          stream_session: stream_session,
          comments: stream_session ? Comment.alive.where(stream_session: stream_session)
                                       .order(created_at: :desc).limit(50).reverse : [],
          drink_items: booth.store.drink_items.with_attached_custom_icon.enabled_only.ordered,
          can_create_drink_order: authenticated_viewer && stream_session.present?,
          authenticated_viewer: authenticated_viewer
        }
      )
    end
  end

  def self.broadcast_ended(stream_session, forced: false)
    Turbo::StreamsChannel.broadcast_replace_to(
      [ stream_session, :cast_pending_drink_orders ],
      target: "cast_pending_drink_orders",
      partial: "cast/stream_sessions/ended",
      locals: {
        stream_session: stream_session,
        forced: forced
      }
    )

    %i[authenticated guest].each do |variant|
      Turbo::StreamsChannel.broadcast_update_to(
        [ stream_session.booth, :stream_state, variant ],
        target: "flash_inner",
        partial: "shared/flash_message",
        locals: { level: "secondary", message: "配信が終了しました。未消化ドリンクは返却されました。" }
      )
    end
  end
end
