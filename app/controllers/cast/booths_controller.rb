# frozen_string_literal: true

module Cast
  class BoothsController < Cast::BaseController
    before_action :set_booth, only: %i[show live status edit update]
    before_action :authorize_update!, only: %i[edit update]

    def index
      @booths =
        if current_user.system_admin?
          Booth.order(:id)
        else
          Booth.joins(:booth_casts)
              .where(booth_casts: { cast_user_id: current_user.id })
              .order(:id)
        end

      @current_booth_id = session[:current_booth_id]
      @confirm_switch_booth = current_booth.present? && !current_booth.offline?
    end

    # Summary（offline専用）
    def show
      # ★offline以外（standby/live/away）は配信画面へ寄せる
      unless @booth.offline?
        redirect_to live_cast_booth_path(@booth)
        nil
      end
    end

    # Live UI（standby/live/away）
    def live
      @stream_session = @booth.current_stream_session

      # ★offline で live に来たら summary へ
      if @booth.offline? || @stream_session.blank?
        redirect_to cast_booth_path(@booth), alert: "配信セッションがありません（まずスタンバイ開始してください）"
        return
      end

      @comments =
        Comment.alive.where(stream_session: @stream_session)
               .order(created_at: :desc)
               .limit(50)
               .reverse
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
      booth = StreamSessions::StatusService.new(
        booth: @booth,
        actor: current_user,
        to_status: params[:to]
      ).call

      StreamSessionNotifier.broadcast_stream_state(booth: booth)

      respond_to do |format|
        format.html { redirect_to live_cast_booth_path(@booth), notice: "状態更新: #{params[:to]}" }
        format.turbo_stream { head :no_content }
        format.json { render json: { ok: true }, status: :ok }
        format.any { head :no_content }
      end
    rescue => e
      respond_to do |format|
        format.html { redirect_to live_cast_booth_path(@booth), alert: e.message }
        format.turbo_stream { render plain: e.message, status: :unprocessable_entity }
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
        format.any { render plain: e.message, status: :unprocessable_entity }
      end
    end

    private

    def set_booth
      booth = Booth.find(params[:id])

      unless current_user.system_admin? || BoothCast.exists?(cast_user_id: current_user.id, booth_id: booth.id)
        session.delete(:current_booth_id)
        head :forbidden
        return
      end

      @booth = booth
      session[:current_booth_id] = @booth.id
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
