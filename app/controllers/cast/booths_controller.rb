# frozen_string_literal: true

module Cast
  class BoothsController < Cast::BaseController
    include RemovableImageAttachment

    before_action :set_booth, only: %i[live status edit update]
    before_action :authorize_update!, only: %i[edit update]

    def index
      @booths =
        if current_user.system_admin?
          Booth.order(:id)
        elsif current_user.at_least?(:store_admin)
          Booth.joins(store: :store_memberships)
              .where(store_memberships: { user_id: current_user.id, membership_role: :admin })
              .distinct
              .order(:id)
        else
          Booth.joins(:booth_casts)
              .where(booth_casts: { cast_user_id: current_user.id })
              .order(:id)
        end

      @current_booth_id = session[:current_booth_id]
      @confirm_switch_booth = current_booth&.live? || current_booth&.away?
    end

    def live
      @stream_session = @booth.current_stream_session

      if @stream_session.blank?
        redirect_to cast_booths_path, alert: "配信セッションがありません（配信導線から入り直してください）"
        return
      end

      @comments =
        Comment.alive.where(stream_session: @stream_session)
               .order(created_at: :desc)
               .limit(50)
               .reverse

      @banuba_client_token = ENV["BANUBA_CLIENT_TOKEN"].to_s
      @banuba_sdk_base_url = "/banuba/sdk"
      @banuba_face_tracker_url = "/banuba/modules/face_tracker.zip"
      @banuba_eyes_url = "/banuba/modules/eyes.zip"
      @banuba_lips_url = "/banuba/modules/lips.zip"
      @banuba_skin_url = "/banuba/modules/skin.zip"
      @banuba_effect_url = "/banuba/effects/beauty_base.zip"
      @banuba_effect_name = "beauty_base.zip"
    end

    def edit
    end

    def update
      if @booth.update(booth_params)
        purge_attachment_if_requested(
          record: @booth,
          attachment_name: :thumbnail_image,
          remove_param_name: :remove_thumbnail_image
        )

        redirect_to cast_booths_path, notice: "更新しました"
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

      stream_session = booth.current_stream_session
      comments =
        if stream_session
          Comment.alive.where(stream_session: stream_session)
                .order(created_at: :desc).limit(50).reverse
        else
          []
        end

      respond_to do |format|
        format.html { redirect_to live_cast_booth_path(@booth), notice: "状態更新: #{params[:to]}" }

        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(
              "cast_comment_section",
              partial: "cast/booths/comment_section",
              locals: { booth: booth, stream_session: stream_session, comments: comments }
            )
          ]
        end

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
      booth = Booth.active.find(params[:id])

      allowed =
        if current_user.system_admin?
          true
        elsif current_user.at_least?(:store_admin)
          current_user.admin_of_store?(booth.store_id)
        else
          BoothCast.exists?(cast_user_id: current_user.id, booth_id: booth.id)
        end

      unless allowed
        session.delete(:current_booth_id)
        head :forbidden
        return
      end

      @booth = booth
      session[:current_booth_id] = @booth.id
      session[:current_store_id] = @booth.store_id
    end

    def authorize_update!
      policy = Authorization::BoothPolicy.new(current_user, @booth)
      head :forbidden unless policy.update?
    end

    def booth_params
      params.require(:booth).permit(:description, :thumbnail_image)
    end
  end
end
