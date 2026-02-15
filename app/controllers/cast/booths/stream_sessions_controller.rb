# frozen_string_literal: true

module Cast
  module Booths
    class StreamSessionsController < Cast::BaseController
      def create
        booth = current_booth
        if booth.blank?
          redirect_to cast_booths_path, alert: "選択できないブースです"
          return
        end

        session = StreamSessions::StartService.new(
          booth: booth,
          actor: current_user
        ).call

        redirect_to live_cast_booth_path(booth), notice: "スタンバイ開始: session=#{session.id}"
      rescue => e
        redirect_to cast_booth_path(booth&.id || params[:booth_id]), alert: e.message
      end
    end
  end
end
