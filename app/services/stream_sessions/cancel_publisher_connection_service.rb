module StreamSessions
  class CancelPublisherConnectionService
    def initialize(stream_session:, actor:, request_id:, generation:)
      @stream_session = stream_session
      @actor = actor
      @request_id = request_id
      @generation = PublisherControl.generation(generation)
    end

    def call
      @booth = @stream_session.booth
      connection = nil
      @booth.with_lock do
        @stream_session.lock!
        unless PublisherControl.active_actor?(@actor) && Authorization::BoothPolicy.new(@actor, @booth).update?
          reject!("forbidden", "配信を操作する権限がありません", status: :forbidden)
        end
        stale! unless PublisherControl.valid_request_id?(@request_id) && @generation
        connection = @stream_session.stream_publisher_connections.lock.find_by(request_id: @request_id)
        stale! unless connection && connection.generation == @generation && !@stream_session.ended?

        if connection.disconnect_reason == "cancel"
          unless @stream_session.publisher_generation == connection.generation + 1 &&
              [ nil, connection.id ].include?(@stream_session.current_publisher_connection_id)
            stale!
          end
        else
          stale! unless @stream_session.current_publisher_connection_id == connection.id &&
            @stream_session.publisher_generation == connection.generation
          unless @booth.current_stream_session_id == @stream_session.id && !@booth.archived?
            reject!("not_joinable", "この配信セッションでは操作できません")
          end
          return PublisherStateService.payload(connection: connection, stream_session: @stream_session) if connection.confirmed_at

          recording_state = @stream_session.publisher_recording_state
          if recording_state == :recorded && (!@stream_session.actual_publisher?(@actor) || connection.user_id != @actor.id)
            reject!("forbidden", "実際に配信している本人だけが復帰を取り消せます", status: :forbidden)
          end
          unless %i[not_started recorded].include?(recording_state)
            reject!("publisher_state_unavailable", "配信状態を確認できません。再確認してください", status: :service_unavailable)
          end
          @stream_session.update!(publisher_generation: connection.generation + 1)
          connection.update!(disconnect_requested_at: Time.current, disconnect_reason: "cancel")
        end

        connection = Ivs::DisconnectPublisherConnectionService.new(connection_id: connection.id).call
        ActiveRecord.after_all_transactions_commit do
          if connection.reload.released_at
            StreamSession.where(id: @stream_session.id, current_publisher_connection_id: connection.id,
              publisher_generation: connection.generation + 1).update_all(current_publisher_connection_id: nil)
          end
        end
      end
      PublisherStateService.payload(connection: connection.reload, stream_session: @stream_session.reload)
    end

    private

    def stale!
      reject!("stale_publisher_request", "配信の状態が更新されています。画面を読み込み直してください")
    end

    def reject!(code, message, status: :conflict)
      raise PublisherControl::Error.new(code: code, message: message, booth: @booth, status: status)
    end
  end
end
