# frozen_string_literal: true

class StreamSessionNotifier
  def self.broadcast_publisher_disconnect(connection)
    session = connection.stream_session.reload
    booth = connection.booth
    routes = Rails.application.routes.url_helpers
    if session.ended?
      Turbo::StreamsChannel.broadcast_replace_to([ session, :publisher_disconnect ],
        target: "publisher_disconnect_session_#{session.id}", partial: "shared/publisher_disconnect_status",
        locals: { status: StreamSessions::PublisherStateService.ended_payload(stream_session: session),
          target_id: "publisher_disconnect_session_#{session.id}", state_url: routes.disconnect_state_cast_stream_session_path(session) })
    end
    Turbo::StreamsChannel.broadcast_replace_to([ booth, :publisher_disconnect ],
      target: "publisher_disconnect_booth_#{booth.id}", partial: "shared/publisher_disconnect_status",
      locals: { status: Ivs::RetryPublisherDisconnectsService.state_for(StreamPublisherConnection.disconnect_pending.unreleased.where(booth: booth)),
        target_id: "publisher_disconnect_booth_#{booth.id}", state_url: routes.publisher_disconnect_state_cast_booth_path(booth) })
  rescue StandardError => error
    Rails.logger.error("publisher_disconnect_notification_failed connection_id=#{connection.id} error=#{error.class.name}")
  end

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
