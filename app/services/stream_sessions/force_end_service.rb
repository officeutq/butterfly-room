# frozen_string_literal: true

module StreamSessions
  class ForceEndService
    def initialize(stream_session:, actor:)
      @stream_session = stream_session
      @actor = actor
    end

    def call
      disconnect_publisher_participant
      ended_session = StreamSessions::EndService.new(
        stream_session: @stream_session,
        actor: @actor
      ).call

      StreamSessionNotifier.broadcast_ended(ended_session, forced: true)
    end

    private

    def disconnect_publisher_participant
      stage_arn = @stream_session.ivs_stage_arn
      return if stage_arn.blank?

      client = Ivs::Client.build
      participants = client.list_participants(stage_arn: stage_arn)

      target = participants.find do |participant|
        attrs = participant.attributes || {}

        attrs["stream_session_id"] == @stream_session.id.to_s &&
          attrs["role"] == Ivs::CreateParticipantTokenService::ROLE_PUBLISHER
      end

      if target.blank?
        Rails.logger.info(
          "[ForceEnd] publisher participant not found " \
          "stream_session_id=#{@stream_session.id} stage_arn=#{stage_arn}"
        )
        return
      end

      client.disconnect_participant(
        stage_arn: stage_arn,
        session_id: target.stage_session_id,
        participant_id: target.participant_id
      )

      Rails.logger.info(
        "[ForceEnd] publisher participant disconnected " \
        "stream_session_id=#{@stream_session.id} " \
        "stage_session_id=#{target.stage_session_id} " \
        "participant_id=#{target.participant_id}"
      )
    rescue Aws::IVSRealTime::Errors::ServiceError => e
      Rails.logger.error(
        "[ForceEnd][IVS] #{e.class}: #{e.message} " \
        "stream_session_id=#{@stream_session.id} stage_arn=#{stage_arn}"
      )
    rescue => e
      Rails.logger.error(
        "[ForceEnd] #{e.class}: #{e.message} " \
        "stream_session_id=#{@stream_session.id} stage_arn=#{stage_arn}"
      )
    end
  end
end
