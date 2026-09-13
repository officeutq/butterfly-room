# frozen_string_literal: true

module StreamSessions
  class PublishService
    class PublicationPending < PublisherControl::Conflict; end
    TOKEN_MINUTES = 1
    EXPIRY_MARGIN = 30.seconds
    Result = Data.define(:token, :attempt_id)

    def initialize(stream_session:, actor:, attempt_id:, client: Ivs::Client.build)
      @session = stream_session
      @actor = actor
      @attempt_id = attempt_id.to_s
      @client = client
    end

    def issue_token
      raise PublisherControl::Conflict, "画面を再読み込みしてください" unless @attempt_id.match?(/\A[0-9a-f-]{36}\z/i)

      # 外部発行より先に確保をコミットする。応答消失でも予約は消さない。
      attempt = PublisherControl.lock_session(@session, @actor) do |session, booth|
        PublisherControl.release_expired_attempts!(@actor, booth: booth, client: @client)
        PublisherControl.validate!(session, booth, @actor)
        ensure_no_connected_publishers!(session)
        if StreamPublishAttempt.exists?(request_id: @attempt_id) ||
            StreamPublishAttempt.open.joins(:stream_session).where(stream_sessions: { booth_id: booth.id }).exists?
          raise PublisherControl::Conflict, "開始処理が残っています。接続を終了し、しばらく待って再試行してください"
        end
        StreamPublishAttempt.create!(stream_session: session, user: @actor, request_id: @attempt_id,
          expires_at: Time.current + TOKEN_MINUTES.minutes + EXPIRY_MARGIN)
      end

      PublisherControl.lock_session(@session, @actor) do |session, booth|
        PublisherControl.validate!(session, booth, @actor)
        attempt.reload
        raise PublisherControl::Conflict, "開始処理は取り消されました" if attempt.cancelled_at || attempt.retired_at

        token = @client.create_participant_token(stage_arn: session.ivs_stage_arn,
          duration: TOKEN_MINUTES, capabilities: %w[PUBLISH], user_id: @actor.id.to_s,
          attributes: { "role" => "publisher", "stream_session_id" => session.id.to_s,
            "user_id" => @actor.id.to_s, "publish_attempt_id" => attempt.request_id })
        raise PublisherControl::Conflict, "配信トークンの応答を確認できません" if token.participant_id.blank? || token.expiration_time.blank?

        attempt.update!(participant_id: token.participant_id, expires_at: token.expiration_time + EXPIRY_MARGIN)
        Result.new(token: token.token, attempt_id: attempt.request_id)
      end
    end

    def confirm
      result = PublisherControl.lock_session(@session, @actor) do |session, booth|
        PublisherControl.validate!(session, booth, @actor)
        attempt = current_attempt!(session)
        participants = @client.list_participants(stage_arn: session.ivs_stage_arn)
        participant = participants.find { |p| p.participant_id == attempt.participant_id }
        attrs = participant&.attributes || {}
        unless participant&.state == "CONNECTED" && participant.published &&
            attrs["role"] == "publisher" && attrs["user_id"] == @actor.id.to_s &&
            attrs["stream_session_id"] == session.id.to_s && attrs["publish_attempt_id"] == attempt.request_id
          raise PublicationPending, "IVSで配信を確認中です。再試行してください"
        end
        ensure_no_connected_publishers!(session, participants: participants, except: attempt.participant_id)
        now = Time.current
        unless session.broadcast_started_by_user_id
          session.update!(broadcast_started_by_user: @actor, broadcast_started_at: now,
            broadcast_identity_source: "ivs_confirmed",
            broadcast_identity_evidence: { attempt_id: attempt.request_id, participant_id: attempt.participant_id, recorded_at: now.iso8601 })
        end
        attempt.update!(confirmed_at: now) unless attempt.confirmed_at
        booth.update!(status: :live, last_online_at: now) if booth.standby?
        session
      end
      StreamSessionNotifier.broadcast_stream_state(booth: result.booth)
      result
    end

    def cancel
      PublisherControl.lock_session(@session, @actor) do |session, _booth|
        attempt = session.stream_publish_attempts.find_by!(request_id: @attempt_id, user: @actor)
        return if attempt.retired_at

        # キャンセルを先に永続化して確定要求を拒否する。切断失敗時も権利は保持。
        attempt.update!(cancelled_at: Time.current) unless attempt.cancelled_at
      end
      PublisherControl.lock_session(@session, @actor) do |session, _booth|
        attempt = session.stream_publish_attempts.find_by!(request_id: @attempt_id, user: @actor)
        @client.disconnect_participant(stage_arn: session.ivs_stage_arn, participant_id: attempt.participant_id) if attempt.participant_id && !attempt.retired_at
      end
    end

    private

    def current_attempt!(session)
      attempt = session.stream_publish_attempts.open.find_by(request_id: @attempt_id, user: @actor)
      raise PublisherControl::Conflict, "古い接続からの操作です。画面を再読み込みしてください" unless attempt&.usable?

      attempt
    end

    def ensure_no_connected_publishers!(session, participants: nil, except: nil)
      participants ||= @client.list_participants(stage_arn: session.ivs_stage_arn)
      if participants.any? { |p| p.state != "DISCONNECTED" && p.participant_id != except && (p.attributes || {})["role"] != "viewer" }
        raise PublisherControl::Conflict, "既存の接続があります。配信元で接続を終了してください"
      end
    end
  end
end
