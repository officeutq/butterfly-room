module StreamSessions
  class PublisherStateService
    def initialize(stream_session:, actor:, request_id:)
      @stream_session = stream_session
      @actor = actor
      @request_id = request_id
    end

    def call
      booth = @stream_session.booth
      unless Authorization::StreamSessionPolicy.new(@actor, @stream_session).publish_token?
        raise PublisherControl::Error.new(code: "forbidden", message: "配信を操作する権限がありません", booth: booth, status: :forbidden)
      end

      booth.with_lock do
        @stream_session.lock!
        connection = @stream_session.stream_publisher_connections.find_by(request_id: @request_id) if PublisherControl.valid_request_id?(@request_id)
        unless connection && connection.user_id == @actor.id
          raise PublisherControl::Error.new(code: "stale_publisher_request", message: "配信の状態が更新されています。画面を読み込み直してください", booth: booth)
        end
        self.class.payload(connection: connection, stream_session: @stream_session)
      end
    end

    # 認可済み・ロック済みの発行／取消からも同じ応答を返す。トークン文字列は含めない。
    def self.payload(connection:, stream_session:, booth: stream_session.booth)
      state =
        if stream_session.ended?
          "ended"
        elsif connection.disconnect_reason == "cancel"
          connection.released_at ? "cancelled" : "cancel_pending"
        elsif connection.released_at || stream_session.current_publisher_connection_id != connection.id ||
            stream_session.publisher_generation != connection.generation
          "superseded"
        elsif connection.confirmed_at
          "confirmed"
        else
          "issued"
        end

      { state: state, stream_session_id: stream_session.id, request_id: connection.request_id,
        generation: connection.generation, current_generation: stream_session.publisher_generation,
        actual_publisher_user_id: stream_session.actual_publisher_user_id,
        broadcast_started_at: stream_session.broadcast_started_at, booth_status: booth.status,
        disconnect_pending: connection.disconnect_requested_at.present? && connection.disconnected_at.nil? && connection.released_at.nil? }
    end
  end
end
