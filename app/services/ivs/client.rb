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

    def initialize(region: ENV.fetch("AWS_REGION", "ap-northeast-1"))
      @client = Aws::IVSRealTime::Client.new(region: region)
    end

    # returns stage arn
    def create_stage!(name:, tags: {})
      resp = @client.create_stage(name: name, tags: tags)
      resp.stage.arn
    end

    def list_participants(stage_arn:)
      ParticipantSnapshotService.new(stage_arn: stage_arn, client: @client).call.participants
    end

    def disconnect_participant(stage_arn:, participant_id:)
      @client.disconnect_participant(
        stage_arn: stage_arn,
        participant_id: participant_id
      )
    end
  end
end
