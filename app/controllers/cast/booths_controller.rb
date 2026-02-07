module Cast
  class BoothsController < Cast::BaseController
    before_action :set_booth, only: %i[show status edit update]
    before_action :authorize_update!, only: %i[edit update]

    def index
      @booths = Booth.order(:id)
    end

    def show
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

    def edit
    end

    def update
      if remove_thumbnail_image?
        @booth.thumbnail_image.purge_later if @booth.thumbnail_image.attached?
      end

      if @booth.update(booth_params)
        redirect_to cast_booth_path(@booth), notice: "更新しました"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def status
      StreamSessions::StatusService.new(
        booth: @booth,
        actor: current_user,
        to_status: params[:to]
      ).call

      respond_to do |format|
        format.html { redirect_to cast_booth_path(@booth), notice: "状態更新: #{params[:to]}" }
        format.turbo_stream { head :no_content }
        format.json { render json: { ok: true }, status: :ok }
        format.any { head :no_content }
      end
    rescue => e
      respond_to do |format|
        format.html { redirect_to cast_booth_path(@booth), alert: e.message }
        format.turbo_stream { render plain: e.message, status: :unprocessable_entity }
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
        format.any { render plain: e.message, status: :unprocessable_entity }
      end
    end

    private

    def set_booth
      @booth = Booth.find(params[:id])
    end

    def authorize_update!
      policy = Authorization::BoothPolicy.new(current_user, @booth)
      head :forbidden unless policy.update?
    end

    def booth_params
      params.require(:booth).permit(:description, :thumbnail_image)
    end

    def remove_thumbnail_image?
      params.dig(:booth, :remove_thumbnail_image) == "1"
    end
  end
end
