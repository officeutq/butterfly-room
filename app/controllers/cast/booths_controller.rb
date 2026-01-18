module Cast
  class BoothsController < Cast::BaseController
    def index
      @booths = Booth.order(:id)
    end

    def show
      @booth = Booth.find(params[:id])
      @stream_session = @booth.current_stream_session
      @comments =
        if @stream_session.present?
          Comment.alive.where(stream_session: @stream_session)
                .order(created_at: :desc)
                .limit(50)
                .reverse
        else
          []
        end
    end

    def status
      booth = Booth.find(params[:id])

      StreamSessions::StatusService.new(
        booth: booth,
        actor: current_user,
        to_status: params[:to]
      ).call

      redirect_to cast_booth_path(booth), notice: "状態更新: #{params[:to]}"
    rescue => e
      redirect_to cast_booth_path(booth), alert: e.message
    end
  end
end
