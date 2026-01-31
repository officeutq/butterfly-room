# frozen_string_literal: true

module Ivs
  class CreateParticipantTokenService
    class Error < StandardError; end
    class InvalidRole < Error; end
    class NotJoinable < Error; end
    class NotAuthorized < Error; end
    class StageNotBound < Error; end

    ROLE_PUBLISHER = "publisher"
    ROLE_VIEWER    = "viewer"

    def initialize(stream_session:, actor:, role:)
      @stream_session = stream_session
      @actor = actor
      @role = role.to_s
    end

    def call
      validate_role!
      validate_joinable!
      authorize!

      client = Aws::IVSRealTime::Client.new(region: ENV.fetch("AWS_REGION", "ap-northeast-1"))

      resp = client.create_participant_token(
        stage_arn: @stream_session.ivs_stage_arn,
        capabilities: capabilities_for(@role),
        attributes: attributes_for(@role)
      )

      resp.participant_token.token
    end

    private

    def validate_role!
      return if [ ROLE_PUBLISHER, ROLE_VIEWER ].include?(@role)
      raise InvalidRole, "role must be publisher or viewer (given=#{@role})"
    end

    def validate_joinable!
      raise StageNotBound, "ivs_stage_arn is blank" if @stream_session.ivs_stage_arn.blank?

      booth = @stream_session.booth

      joinable =
        @stream_session.live? &&
        %w[live away].include?(booth.status) &&
        booth.current_stream_session_id == @stream_session.id

      raise NotJoinable, "not joinable" unless joinable
    end

    def authorize!
      policy = Authorization::StreamSessionPolicy.new(@actor, @stream_session)

      ok =
        case @role
        when ROLE_PUBLISHER then policy.publish_token?
        when ROLE_VIEWER    then policy.view_token?
        else false
        end

      raise NotAuthorized, "forbidden" unless ok
    end

    def capabilities_for(role)
      case role
      when ROLE_PUBLISHER then %w[PUBLISH]
      when ROLE_VIEWER    then %w[SUBSCRIBE]
      end
    end

    def attributes_for(role)
      # attributes は参加者に見える可能性があるので最小限
      {
        "user_id" => @actor.id.to_s,
        "role" => role,
        "stream_session_id" => @stream_session.id.to_s
      }
    end
  end
end
