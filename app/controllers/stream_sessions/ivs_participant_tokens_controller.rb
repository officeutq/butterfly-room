# frozen_string_literal: true

module StreamSessions
  class IvsParticipantTokensController < ApplicationController
    before_action :authenticate_user!

    def create
      stream_session = StreamSession.find(params[:stream_session_id])
      role = params.require(:role)

      token = Ivs::CreateParticipantTokenService.new(
        stream_session: stream_session,
        actor: current_user,
        role: role
      ).call

      render json: {
        stream_session_id: stream_session.id,
        ivs_stage_arn: stream_session.ivs_stage_arn,
        role: role,
        participant_token: token
      }
    rescue ActiveRecord::RecordNotFound
      render json: { error: "not_found" }, status: :not_found
    rescue ActionController::ParameterMissing
      render json: { error: "missing_role" }, status: :unprocessable_entity
    rescue Ivs::CreateParticipantTokenService::InvalidRole
      render json: { error: "invalid_role" }, status: :unprocessable_entity
    rescue Ivs::CreateParticipantTokenService::StageNotBound
      render json: { error: "stage_not_bound" }, status: :conflict
    rescue Ivs::CreateParticipantTokenService::NotJoinable
      render json: { error: "not_joinable" }, status: :conflict
    rescue Ivs::CreateParticipantTokenService::NotAuthorized
      render json: { error: "forbidden" }, status: :forbidden
    end
  end
end
