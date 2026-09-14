module Ivs
  class ParticipantSnapshotService
    class Unavailable < StandardError; end

    Snapshot = Data.define(:stage_arn, :session_id, :participants)

    def initialize(stage_arn:, client: nil)
      @stage_arn = stage_arn
      @client = client
    end

    def call
      raise Unavailable, "stage_missing" if @stage_arn.blank?

      @client ||= Aws::IVSRealTime::Client.new(region: ENV.fetch("AWS_REGION", "ap-northeast-1"))
      session_id = current_session_id
      participants = session_id ? connected_participants(session_id) : []
      raise Unavailable, "stage_session_changed" unless current_session_id == session_id

      Snapshot.new(stage_arn: @stage_arn, session_id: session_id, participants: participants.freeze)
    rescue Aws::IVSRealTime::Errors::ServiceError, Seahorse::Client::NetworkingError, Aws::Errors::MissingCredentialsError => error
      raise Unavailable, error.class.name
    end

    private

    def current_session_id
      stage = @client.get_stage(arn: @stage_arn).stage
      raise Unavailable, "stage_mismatch" unless stage&.arn == @stage_arn

      stage.active_session_id.presence
    end

    def connected_participants(session_id)
      summaries = []
      seen_tokens = []
      next_token = nil
      loop do
        response = @client.list_participants(stage_arn: @stage_arn, session_id: session_id, next_token: next_token)
        summaries.concat(response.participants)
        next_token = response.next_token.presence
        break unless next_token
        raise Unavailable, "repeated_page_token" if seen_tokens.include?(next_token)

        seen_tokens << next_token
      end

      summaries.filter_map do |summary|
        raise Unavailable, "participant_state_missing" unless %w[CONNECTED DISCONNECTED].include?(summary.state)
        next if summary.state == "DISCONNECTED"
        raise Unavailable, "participant_id_missing" if summary.participant_id.blank?

        participant = @client.get_participant(stage_arn: @stage_arn, session_id: session_id,
          participant_id: summary.participant_id).participant
        unless participant&.participant_id == summary.participant_id && participant.state == "CONNECTED"
          raise Unavailable, "participant_changed"
        end
        participant
      end
    end
  end
end
