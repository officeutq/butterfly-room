# frozen_string_literal: true

module Cast
  module Booths
    class StreamSessionsController < Cast::BaseController
      before_action :set_booth_for_history, only: %i[index]

      def index
        @stream_sessions =
          @booth
            .stream_sessions
            .ended
            .includes(StreamSessions::PublisherControl.enabled? ? { actual_publisher_user: { avatar_attachment: :blob } } : :started_by_cast_user)
            .order(started_at: :desc, id: :desc)
      end

      def create
        booth = Booth.active.find(params[:booth_id])
        return head :forbidden unless Authorization::BoothPolicy.new(current_user, booth).update?
        return unless require_selected_booth!(booth, return_to_key: "booth_live", allow_selection: true)

        result = ::Booths::EnterAsCastService.new(
          booth: booth,
          actor: current_user
        ).call

        case result.action
        when :redirect_live
          redirect_to live_cast_booth_path(result.booth), notice: "配信画面を開きました"
        when :occupied_by_other
          redirect_to cast_booth_path(booth), alert: "このブースはすでに配信中です"
        when :already_live_elsewhere
          redirect_to dashboard_path, alert: "他のブースで配信中のため開始できません"
        else
          redirect_to cast_booth_path(booth), alert: "配信導線の開始に失敗しました"
        end
      rescue ::Booths::EnterAsCastService::NotAuthorized
        redirect_to dashboard_path, alert: "選択できないブースです"
      end

      private

      def set_booth_for_history
        @booth = Booth.find(params[:booth_id])
        unless Authorization::BoothPolicy.new(current_user, @booth).update?
          head :forbidden
          return
        end

        return if current_user.cast? && @booth.archived?

        require_selected_booth!(@booth, return_to_key: "booth_stream_sessions")
      end
    end
  end
end
