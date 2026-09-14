module StreamSessions
  class ConfirmPublisherService
    def initialize(stream_session:, actor:, request_id:, generation:)
      @stream_session = stream_session
      @actor = actor
      @request_id = request_id
      @generation = PublisherControl.generation(generation)
    end

    def call
      @booth = @stream_session.booth
      result = @booth.with_lock do
        @stream_session.lock!
        unless Authorization::StreamSessionPolicy.new(@actor, @stream_session).publish_token?
          reject!("forbidden", "配信を操作する権限がありません", status: :forbidden)
        end
        stale! unless PublisherControl.valid_request_id?(@request_id) && @generation
        connection = @stream_session.stream_publisher_connections.lock.find_by(request_id: @request_id)
        unless connection && connection.user_id == @actor.id && connection.generation == @generation &&
            @stream_session.publisher_generation == @generation && @stream_session.current_publisher_connection_id == connection.id &&
            connection.released_at.nil? && connection.disconnect_requested_at.nil?
          stale!
        end
        validate_target!(connection)
        if connection.confirmed_at
          unavailable! unless @stream_session.actual_publisher?(@actor) && @stream_session.publisher_recording_state == :recorded
          return PublisherStateService.payload(connection: connection, stream_session: @stream_session, booth: @booth)
        end
        unless @stream_session.publisher_recording_state == :not_started ||
            (@stream_session.actual_publisher?(@actor) && @stream_session.publisher_recording_state == :recorded)
          unavailable!
        end

        snapshot = Ivs::ParticipantSnapshotService.new(stage_arn: connection.ivs_stage_arn).call
        verify_participant!(snapshot, connection)
        now = Time.current
        if @stream_session.actual_publisher_user_id.nil?
          @stream_session.update!(actual_publisher_user: @actor, actual_publisher_source: "ivs_verified",
            actual_publisher_recorded_at: now, broadcast_started_at: now,
            actual_publisher_evidence: { request_id: connection.request_id, participant_id: connection.ivs_participant_id,
              ivs_session_id: snapshot.session_id })
        end
        connection.update!(confirmed_at: now)
        @booth.update!(status: :live, last_online_at: now)
        ActiveRecord.after_all_transactions_commit { StreamSessionNotifier.broadcast_stream_state(booth: @booth) }
        PublisherStateService.payload(connection: connection, stream_session: @stream_session, booth: @booth)
      end
      result
    rescue Ivs::ParticipantSnapshotService::Unavailable
      unavailable!
    end

    private

    def validate_target!(connection)
      unless @booth.current_stream_session_id == @stream_session.id && !@booth.archived? &&
          @stream_session.live? && @stream_session.ended_at.nil? && %w[standby live away].include?(@booth.status)
        reject!("not_joinable", "この配信セッションでは開始できません")
      end
      if connection.ivs_stage_arn.blank? || connection.ivs_stage_arn != @stream_session.ivs_stage_arn ||
          connection.ivs_stage_arn != @booth.ivs_stage_arn || connection.booth_id != @booth.id
        reject!("stage_mismatch", "ブースの配信接続を確認できません")
      end
      unavailable! if connection.ivs_participant_id.blank? || connection.token_expires_at.nil?
    end

    def verify_participant!(snapshot, connection)
      expected = snapshot.participants.select { |participant| participant.participant_id == connection.ivs_participant_id }
      unavailable! unless snapshot.session_id.present? && expected.size == 1
      participant = expected.first
      attributes = participant.attributes.to_h
      unless participant.state == "CONNECTED" && participant.published == true &&
          attributes["role"] == "publisher" && attributes["stream_session_id"] == @stream_session.id.to_s &&
          attributes["user_id"] == @actor.id.to_s
        unavailable!
      end
      snapshot.participants.each do |other|
        next if other.participant_id == participant.participant_id
        other_attributes = other.attributes.to_h
        unless other_attributes["role"] == "viewer" && other_attributes["stream_session_id"] == @stream_session.id.to_s && other.published == false
          unavailable!
        end
      end
    end

    def unavailable!
      reject!("publisher_state_unavailable", "配信状態を確認できません。再確認してください", status: :service_unavailable)
    end

    def stale!
      reject!("stale_publisher_request", "配信の状態が更新されています。画面を読み込み直してください")
    end

    def reject!(code, message, status: :conflict)
      raise PublisherControl::Error.new(code: code, message: message, booth: @booth, status: status)
    end
  end
end
