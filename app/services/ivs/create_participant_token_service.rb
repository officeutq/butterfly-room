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

      if @role == ROLE_PUBLISHER
        Stores::PublicationGuard.with_lock(booth: @stream_session.booth) do
          Stores::PublicationGuard.ensure_published!(booth: @stream_session.booth)
          issue_token
        end
      else
        issue_token
      end
    end

    def joinable?
      return false if @stream_session.ivs_stage_arn.blank?

      booth = @stream_session.booth
      return false if booth.current_stream_session_id != @stream_session.id

      booth_status = booth.status.to_s

      case @role
      when ROLE_PUBLISHER
        # Issue #78: standby でも publisher は join/publish してよい
        %w[standby live away].include?(booth_status)
      when ROLE_VIEWER
        # Issue #78: viewer は live/away のみ
        %w[live away].include?(booth_status)
      else
        false
      end
    end

    private

    def issue_token
      client = Aws::IVSRealTime::Client.new(region: ENV.fetch("AWS_REGION", "ap-northeast-1"))
      response = client.create_participant_token(
        stage_arn: @stream_session.ivs_stage_arn,
        capabilities: capabilities_for(@role),
        attributes: attributes_for(@role)
      )
      response.participant_token.token
    end

    def validate_role!
      return if [ ROLE_PUBLISHER, ROLE_VIEWER ].include?(@role)
      raise InvalidRole, "role must be publisher or viewer (given=#{@role})"
    end

    def validate_joinable!
      raise StageNotBound, "ivs_stage_arn is blank" if @stream_session.ivs_stage_arn.blank?
      raise NotJoinable, "not joinable" unless joinable?
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
      attributes = {
        "role" => role,
        "stream_session_id" => @stream_session.id.to_s
      }

      attributes["user_id"] = @actor.id.to_s if @actor.present?
      attributes
    end
  end
end
