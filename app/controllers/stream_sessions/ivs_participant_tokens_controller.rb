# frozen_string_literal: true

module StreamSessions
  class IvsParticipantTokensController < ApplicationController
    before_action :authenticate_user!

    def create
      stream_session = StreamSession.find(params[:stream_session_id])
      role = params.require(:role)
      booth = stream_session.booth

      # booth 固定 stage と stream_session の stage が一致しないのは不整合（事故/旧データ混在）
      # すぐに 409 で止める
      if booth.ivs_stage_arn.present? && stream_session.ivs_stage_arn != booth.ivs_stage_arn
        return render json: { error: "stage_mismatch" }, status: :conflict
      end

      case role
      when "viewer"
        # スタンバイ中は viewer を join させない（Issue #78）
        unless booth.current_stream_session_id == stream_session.id && (booth.live? || booth.away?)
          return render json: { error: "not_joinable" }, status: :conflict
        end

        # viewer 側トリガで stage を作らせない（事故防止）
        # NOTE:
        # Stage 作成は booth 側で完了している前提。
        # token 発行のリクエストをトリガに Stage を作らせない（accidental create 防止）。
        if stream_session.ivs_stage_arn.blank?
          return render json: { error: "stage_not_bound" }, status: :conflict
        end

      when "publisher"
        # publisher はスタンバイでも token 取得 OK（ただし current_session 一致は必須）
        unless booth.current_stream_session_id == stream_session.id && booth.status.to_sym.in?(%i[standby live away])
          return render json: { error: "not_joinable" }, status: :conflict
        end

        # Stage 未束縛ならエラー（作成は booth 作成時に完了している前提）
        # NOTE:
        # Stage 作成は booth 側で完了している前提。
        # token 発行のリクエストをトリガに Stage を作らせない（accidental create 防止）。
        if stream_session.ivs_stage_arn.blank?
          return render json: { error: "stage_not_bound" }, status: :conflict
        end

      else
        return render json: { error: "invalid_role" }, status: :unprocessable_entity
      end

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
