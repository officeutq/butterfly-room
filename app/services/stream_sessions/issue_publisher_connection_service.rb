module StreamSessions
  class IssuePublisherConnectionService
    def initialize(stream_session:, actor:, request_id:, expected_generation:)
      @stream_session = stream_session
      @actor = actor
      @request_id = request_id
      @expected_generation = PublisherControl.generation(expected_generation)
    end

    def call
      @booth = @stream_session.booth
      @booth.with_lock do
        @stream_session.lock!
        authorize!
        validate_request!
        existing = StreamPublisherConnection.find_by(request_id: @request_id)
        return_existing_request!(existing) if existing
        stale! unless @stream_session.publisher_generation == @expected_generation
        validate_target!

        if StreamPublisherConnection.unreleased.where(user_id: @actor.id).exists? ||
            StreamPublisherConnection.unreleased.where(booth_id: @booth.id).exists?
          reject!("publisher_in_use", "配信の開始処理または接続の確認が進行中です")
        end

        Booths::ValidatePublisherEntryService.new(booth: @booth, actor: @actor).call
        # 成功済みの再接続は#1302で旧参加者の切断と組み合わせる。
        unless @stream_session.publisher_recording_state == :not_started
          reject!("publisher_in_use", "配信中の接続から復帰してください")
        end

        connection = @stream_session.stream_publisher_connections.create!(
          request_id: @request_id, booth: @booth, user: @actor,
          generation: @expected_generation + 1, ivs_stage_arn: @stream_session.ivs_stage_arn
        )
        token = create_token
        if token&.token.blank? || token.participant_id.blank? || token.expiration_time.blank?
          reject!("publisher_state_unavailable", "配信接続を確認できません。再確認してください", status: :service_unavailable)
        end
        connection.update!(ivs_participant_id: token.participant_id, token_expires_at: token.expiration_time)
        @stream_session.update!(publisher_generation: connection.generation, current_publisher_connection: connection)
        @result = PublisherStateService.payload(connection: connection, stream_session: @stream_session).merge(
          participant_token: token.token, participant_id: connection.ivs_participant_id,
          expires_at: connection.token_expires_at, ivs_stage_arn: connection.ivs_stage_arn, role: "publisher"
        )
      end
      @result
    rescue ActiveRecord::RecordNotUnique
      reject!("publisher_in_use", "別の配信開始処理が先に成立しました")
    rescue Aws::IVSRealTime::Errors::ServiceError, Seahorse::Client::NetworkingError, Aws::Errors::MissingCredentialsError
      reject!("publisher_state_unavailable", "配信接続を確認できません。再確認してください", status: :service_unavailable)
    end

    private

    def authorize!
      return if Authorization::StreamSessionPolicy.new(@actor, @stream_session).publish_token?

      reject!("forbidden", "配信を操作する権限がありません", status: :forbidden)
    end

    def validate_request!
      stale! unless PublisherControl.valid_request_id?(@request_id) && @expected_generation
    end

    def validate_target!
      unless @booth.current_stream_session_id == @stream_session.id && @stream_session.live? &&
          @stream_session.ended_at.nil? && !@booth.archived? && %w[standby live away].include?(@booth.status)
        reject!("not_joinable", "この配信セッションでは開始できません")
      end
      if @stream_session.ivs_stage_arn.blank? || @stream_session.ivs_stage_arn != @booth.ivs_stage_arn
        reject!("stage_mismatch", "ブースの配信接続を確認できません")
      end
    end

    def return_existing_request!(connection)
      stale! unless connection.stream_session_id == @stream_session.id && connection.user_id == @actor.id
      details = PublisherStateService.payload(connection: connection, stream_session: @stream_session)
      reject!("token_already_issued", "開始要求の状態を確認してください", details: details)
    end

    def create_token
      Aws::IVSRealTime::Client.new(region: ENV.fetch("AWS_REGION", "ap-northeast-1")).create_participant_token(
        stage_arn: @stream_session.ivs_stage_arn, capabilities: %w[PUBLISH],
        attributes: { "role" => "publisher", "stream_session_id" => @stream_session.id.to_s, "user_id" => @actor.id.to_s }
      ).participant_token
    end

    def stale!
      reject!("stale_publisher_request", "配信の状態が更新されています。画面を読み込み直してください")
    end

    def reject!(code, message, status: :conflict, details: {})
      raise PublisherControl::Error.new(code: code, message: message, booth: @booth, status: status, details: details)
    end
  end
end
