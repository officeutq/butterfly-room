# frozen_string_literal: true

module Ivs
  class Client
    class << self
      attr_writer :factory

      def build(region: ENV.fetch("AWS_REGION", "ap-northeast-1"))
        return @factory.call(region: region) if @factory.present?

        new(region: region)
      end

      def reset_factory!
        @factory = nil
      end
    end

    def initialize(region: ENV.fetch("AWS_REGION", "ap-northeast-1"), client: nil)
      @client = client || Aws::IVSRealTime::Client.new(region: region, retry_limit: 1, http_open_timeout: 3, http_read_timeout: 5)
    end

    # returns stage arn
    def create_stage!(name:, tags: {})
      resp = @client.create_stage(name: name, tags: tags)
      resp.stage.arn
    end

    def create_participant_token(**options)
      @client.create_participant_token(**options).participant_token
    end

    def list_stage_sessions(stage_arn:)
      sessions = []
      next_token = nil
      loop do
        response = @client.list_stage_sessions(stage_arn: stage_arn, next_token: next_token)
        sessions.concat(response.stage_sessions)
        next_token = response.next_token
        break if next_token.blank?
      end
      sessions
    end

    def list_participants(stage_arn:, session_id: nil)
      session_id ||= @client.get_stage(arn: stage_arn).stage.active_session_id
      return [] if session_id.blank?

      participants = []
      next_token = nil

      loop do
        resp = @client.list_participants(
          stage_arn: stage_arn,
          session_id: session_id,
          next_token: next_token
        )

        participants.concat(resp.participants.map do |summary|
          @client.get_participant(stage_arn: stage_arn, session_id: session_id,
            participant_id: summary.participant_id).participant
        end)
        next_token = resp.next_token
        break if next_token.blank?
      end

      participants
    end

    def disconnect_participant(stage_arn:, participant_id:)
      @client.disconnect_participant(
        stage_arn: stage_arn,
        participant_id: participant_id
      )
    end
  end
end
