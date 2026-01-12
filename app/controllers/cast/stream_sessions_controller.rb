# frozen_string_literal: true

module Cast
  class StreamSessionsController < Cast::BaseController
    def finish
      session = StreamSession.find(params[:id])

      StreamSessions::EndService.new(
        stream_session: session,
        actor: current_user
      ).call

      redirect_to cast_booth_path(session.booth_id), notice: "配信終了"
    rescue => e
      redirect_to cast_booth_path(session.booth_id), alert: e.message
    end

    def pending_drink_orders
      @stream_session_id = params[:id]
    end
  end
end
