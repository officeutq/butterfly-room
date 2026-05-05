# frozen_string_literal: true

module Cast
  module Booths
    class StreamSessionsController < Cast::BaseController
      before_action :require_current_booth!, only: %i[index]

      def index
        @booth = current_booth

        @stream_sessions =
          @booth
            .stream_sessions
            .ended
            .includes(:started_by_cast_user)
            .order(started_at: :desc, id: :desc)
      end

      def create
        booth = current_booth
        if booth.blank?
          redirect_to cast_booths_path, alert: "選択できないブースです"
          return
        end

        result = ::Booths::EnterAsCastService.new(
          booth: booth,
          actor: current_user
        ).call

        case result.action
        when :redirect_live
          redirect_to live_cast_booth_path(result.booth), notice: "配信画面を開きました"
        when :occupied_by_other
          redirect_to cast_booths_path, alert: "このブースはすでに配信中です"
        when :already_live_elsewhere
          redirect_to cast_booths_path, alert: "他のブースで配信中のため開始できません"
        else
          redirect_to cast_booths_path, alert: "配信導線の開始に失敗しました"
        end
      rescue ::Booths::EnterAsCastService::NotAuthorized
        redirect_to cast_booths_path, alert: "選択できないブースです"
      end
    end
  end
end
