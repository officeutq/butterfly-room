# frozen_string_literal: true

module StreamSessions
  class EnsureIvsStageService
    class Error < StandardError; end

    def initialize(stream_session:, ivs_client: Ivs::Client.new)
      @stream_session = stream_session
      @ivs_client = ivs_client
    end

    # returns stage arn
    def call
      @stream_session.with_lock do
        return @stream_session.ivs_stage_arn if @stream_session.ivs_stage_arn.present?

        # 追跡しやすい命名（AWS側の name 制約に引っかかりにくい）
        stage_name = "stream_session-#{@stream_session.id}"

        arn = @ivs_client.create_stage!(name: stage_name)

        @stream_session.update!(ivs_stage_arn: arn)
        arn
      end
    end
  end
end
