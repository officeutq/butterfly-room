module Booths
  # 既存の外側トランザクションを維持し、対象boothをロックして検証する。
  class ValidatePublisherEntryService
    def initialize(booth:, actor:, allow_new: false)
      @booth = booth
      @actor = actor
      @allow_new = allow_new
    end

    def call
      @booth.with_lock { validate! }
    end

    private

    def validate!
      reject!("forbidden", "選択できないブースです", status: :forbidden) unless Authorization::BoothPolicy.new(@actor, @booth).update?
      reject!("not_joinable", "閉鎖済みのブースでは配信できません") if @booth.archived?
      if StreamSession.actually_broadcasting_by(@actor).where.not(booth_id: @booth.id).exists?
        reject!("publisher_in_use", "他のブースで配信中のため開始できません")
      end

      stream_session = @booth.current_stream_session
      if @allow_new && @booth.offline? && @booth.current_stream_session_id.nil?
        verify_external_state!(nil)
        return
      end

      unless stream_session&.booth_id == @booth.id && stream_session.live? && stream_session.ended_at.nil?
        reject!("not_joinable", "配信セッションの状態が更新されています。画面を読み込み直してください")
      end
      if @booth.ivs_stage_arn.blank? || stream_session.ivs_stage_arn != @booth.ivs_stage_arn
        reject!("stage_mismatch", "ブースの配信接続を確認できません")
      end

      case stream_session.publisher_recording_state
      when :not_started
        verify_external_state!(stream_session)
      when :recorded
        unless stream_session.actual_publisher?(@actor)
          reject!("publisher_in_use", "このブースはすでに他の人が配信中です")
        end
        # 本人の復帰画面はDBで判定。新しいトークンの発行時に外部を再確認する。
      else
        reject!("publisher_state_unavailable", "配信状態を確認できません。再確認してください", status: :service_unavailable)
      end
    end

    def verify_external_state!(stream_session)
      snapshot = Ivs::ParticipantSnapshotService.new(stage_arn: @booth.ivs_stage_arn).call
      current_connection = stream_session&.current_publisher_connection
      snapshot.participants.each do |participant|
        attributes = participant.attributes.to_h
        same_session = stream_session && attributes["stream_session_id"] == stream_session.id.to_s
        viewer = attributes["role"] == "viewer" && participant.published == false
        own_publisher = attributes["role"] == "publisher" && attributes["user_id"] == @actor.id.to_s &&
          current_connection&.user_id == @actor.id && current_connection.released_at.nil? &&
          current_connection.stream_session_id == stream_session.id && current_connection.booth_id == @booth.id &&
          current_connection.disconnect_requested_at.nil? && current_connection.ivs_stage_arn == snapshot.stage_arn &&
          current_connection.ivs_participant_id == participant.participant_id &&
          current_connection.generation == stream_session.publisher_generation
        next if same_session && (viewer || own_publisher)

        Rails.logger.warn("publisher_entry_connection_mismatch booth_id=#{@booth.id} " \
          "stream_session_id=#{stream_session&.id} ivs_session_id=#{snapshot.session_id} participant_id=#{participant.participant_id}")
        reject!("publisher_state_unavailable", "配信接続の状態が一致しません。再確認してください", status: :service_unavailable)
      end
    rescue Ivs::ParticipantSnapshotService::Unavailable => error
      Rails.logger.warn("publisher_state_unavailable booth_id=#{@booth.id} reason=#{error.message}")
      reject!("publisher_state_unavailable", "配信状態を確認できません。再確認してください", status: :service_unavailable)
    end

    def reject!(code, message, status: :conflict)
      raise StreamSessions::PublisherControl::Error.new(code: code, message: message, booth: @booth, status: status)
    end
  end
end
