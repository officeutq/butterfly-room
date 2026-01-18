module Cast
  class BoothsController < Cast::BaseController
    def index
      @booths = Booth.order(:id)
    end

    def show
      @booth = Booth.find(params[:id])
      @stream_session = @booth.current_stream_session
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
