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

      respond_to do |format|
        format.html do
          redirect_to cast_booth_path(booth), notice: "状態更新: #{params[:to]}"
        end

        # fetch / Turbo Stream 経由は redirect しない（←これが重要）
        format.turbo_stream { head :no_content }
        format.json { render json: { ok: true }, status: :ok }
        format.any  { head :no_content }
      end
    rescue => e
      respond_to do |format|
        format.html do
          redirect_to cast_booth_path(booth), alert: e.message
        end
        format.turbo_stream { render plain: e.message, status: :unprocessable_entity }
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
        format.any  { render plain: e.message, status: :unprocessable_entity }
      end
    end
  end
end
