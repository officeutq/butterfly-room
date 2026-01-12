module Cast
  module Booths
    class StreamSessionsController < Cast::BaseController
      def create
        booth = Booth.find(params[:booth_id])

        session = StreamSessions::StartService.new(
          booth: booth,
          actor: current_user
        ).call

        redirect_to cast_booth_path(booth), notice: "配信開始: session=#{session.id}"
      rescue => e
        redirect_to cast_booth_path(params[:booth_id]), alert: e.message
      end
    end
  end
end
