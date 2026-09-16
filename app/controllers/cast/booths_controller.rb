# frozen_string_literal: true

module Cast
  class BoothsController < Cast::BaseController
    before_action :set_booth, only: %i[live status edit update]
    before_action :set_booth_for_show, only: %i[show]
    before_action :authorize_update!, only: %i[edit update]
    before_action :check_selected_booth!, only: %i[show edit update live]

    def index
      redirect_to dashboard_path
    end

    def show
    end

    def retry_publisher_disconnect
      return head :not_found unless StreamSessions::PublisherControl.enabled?

      booth = Booth.find(params[:id])
      pending = Ivs::RetryPublisherDisconnectsService.new(booth: booth, actor: current_user).call
      respond_to do |format|
        format.json { render json: { disconnect_pending: pending }, status: pending ? :accepted : :ok }
        format.any do
          if pending
            raise StreamSessions::PublisherControl::Error.new(code: "publisher_disconnect_pending",
              message: "以前の配信接続の切断を確認しています。再確認してください", booth: booth, status: :accepted)
          end
          destination = if booth.archived?
            dashboard_path
          elsif booth.current_stream_session_id
            live_cast_booth_path(booth)
          else
            cast_booth_path(booth)
          end
          redirect_to destination,
            notice: "配信接続の切断を確認しました", status: :see_other
        end
      end
    end

    def select_modal
      result = resolve_current_selection(purpose: params[:source] == "header" ? :normalize : :require_booth)
      return render_selection_problem(selection_error_message(result)) unless save_current_selection(result)
      return render_broadcast_selection_lock if result.broadcast && params[:source] == "header"

      load_selectable_booths
      if current_booth && (!result.booth_switchable? || params[:source] != "header")
        path = selection_return_path(kind: :booth)
        if turbo_frame_request?
          render_select_modal_redirect(path: path)
        else
          redirect_to path
        end
      elsif @booths.empty?
        render_selection_problem("操作可能なブースがありません")
      elsif turbo_frame_request?
        render :select_modal, layout: false, status: :ok
      else
        @selection_modal_url = select_modal_cast_booths_path(request.query_parameters)
        render "shared/selection_required"
      end
    end

    def live
      entry = ::Booths::PrepareSelectedBoothService.new(booth: @booth, actor: current_user).call
      if entry.information_only
        redirect_to cast_booth_path(entry.booth), alert: entry.message
        return
      end
      @booth = entry.booth

      @stream_session = @booth.current_stream_session

      if @stream_session.blank?
        redirect_to cast_booth_path(@booth), alert: "配信セッションがありません（配信導線から入り直してください）"
        return
      end

      @comments =
        Comment.alive.where(stream_session: @stream_session)
               .order(created_at: :desc)
               .limit(50)
               .reverse

      @effects = Effect.enabled_only.ordered
      @beauty_provider = Rails.configuration.x.beauty_provider
      @deepar_effects = []
      @deepar_default_effect = nil

      if @beauty_provider == "deepar"
        @deepar_effects = DeeparEffect.enabled
        @deepar_default_effect = DeeparEffect.default(@deepar_effects)
      end

      @banuba_client_token = ENV["BANUBA_CLIENT_TOKEN"].to_s
      @banuba_sdk_base_url = "/banuba/sdk"
      @banuba_face_tracker_url = "/banuba/modules/face_tracker.zip"
      @banuba_eyes_url = "/banuba/modules/eyes.zip"
      @banuba_lips_url = "/banuba/modules/lips.zip"
      @banuba_skin_url = "/banuba/modules/skin.zip"
      @banuba_background_url = "/banuba/modules/background.zip"
      @banuba_hair_url = "/banuba/modules/hair.zip"

      @banuba_effect_url = "/banuba/effects/beauty_base.zip"
      @banuba_effect_name = "beauty_base.zip"

      @auto_resume_publish =
        if StreamSessions::PublisherControl.enabled?
          @stream_session.actual_publisher?(current_user) && @stream_session.publisher_recording_state == :recorded
        else
          @stream_session.started_by_cast_user_id == current_user.id && (@booth.live? || @booth.away?)
        end
      if StreamSessions::PublisherControl.enabled?
        @publisher_connection = @stream_session.stream_publisher_connections.unreleased.find_by(
          id: @stream_session.current_publisher_connection_id, user_id: current_user.id)
      end
    end

    def edit
      load_cast_memberships_for_booth if current_user.at_least?(:store_admin)
    end

    def update
      attributes = booth_params.to_h.symbolize_keys
      upload = attributes.delete(:thumbnail_image)
      remove_thumbnail_image = attributes.delete(:remove_thumbnail_image)

      begin
        ::Booths::UpdateService.new(
          booth: @booth,
          attributes:,
          actor_user: current_user, source: "web", request_id: request.request_id,
          image_update: image_pair_payload,
          legacy_thumbnail_upload: upload,
          remove_legacy_thumbnail: remove_thumbnail_image
        ).call do |booth|
          next if create_initial_booth_cast_if_requested(booth)

          raise ActiveRecord::RecordInvalid, booth
        end
      rescue ::Booths::UpdateService::StaleImageError
        return respond_booth_update_error(
          @booth.errors.full_messages,
          status: :conflict,
          code: "image_pair_stale"
        )
      rescue ::Booths::UpdateService::ImageUploadError
        return respond_booth_update_error(
          @booth.errors.full_messages,
          status: :service_unavailable,
          code: "image_upload_failed",
          retryable: true
        )
      rescue ActiveRecord::RecordInvalid, ::Booths::UpdateService::Error
        return respond_booth_update_error(@booth.errors.full_messages)
      rescue ActionController::ParameterMissing, ImageAttachments::MultipartPayload::Invalid => error
        @booth.errors.add(:base, error.message)
        return respond_booth_update_error(@booth.errors.full_messages)
      end

      redirect_path =
        if session[:invitation_booth_edit_id].to_s == @booth.id.to_s && session.delete(:redirect_to_home_after_cast_booth_update)
          session.delete(:invitation_booth_edit_id)
          root_path
        else
          cast_booth_path(@booth)
        end

      respond_to do |format|
        format.html { redirect_to redirect_path, notice: "ブースを更新しました" }
        format.json do
          flash[:notice] = "ブースを更新しました"
          render json: { state: "complete", redirect_url: redirect_path }
        end
      end
    end

    def status
      booth = StreamSessions::StatusService.new(
        booth: @booth,
        actor: current_user,
        to_status: params[:to],
        stream_session_id: params[:stream_session_id], request_id: params[:request_id], generation: params[:generation]
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
    rescue StreamSessions::PublisherControl::Error => error
      render_publisher_entry_error(error)
    rescue => e
      respond_to do |format|
        format.html { redirect_to live_cast_booth_path(@booth), alert: e.message }
        format.turbo_stream { render plain: e.message, status: :unprocessable_entity }
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
        format.any { render plain: e.message, status: :unprocessable_entity }
      end
    end

    private

    def image_pair_payload
      return nil if params.dig(:image_pair, :operation).blank?

      ImageAttachments::MultipartPayload.from_params(params)
    rescue TypeError
      raise ImageAttachments::MultipartPayload::Invalid, "画像送信パラメータが不正です。"
    end

    def load_selectable_booths
      @booths = current_selection.booths
      @include_archived = current_user.at_least?(:store_admin)
      @current_booth_id = current_booth&.id
      @return_to = params[:return_to].presence
      @return_to_key = params[:return_to_key].presence
    end

    def render_select_modal_redirect(path:)
      @redirect_path = path
      render :select_modal_redirect, layout: false, status: :ok
    end

    def set_booth
      scope = action_name == "live" && current_user.at_least?(:store_admin) ? Booth.all : Booth.active
      booth = scope.find(params[:id])

      allowed =
        if current_user.system_admin?
          true
        elsif current_user.at_least?(:store_admin)
          current_user.admin_of_store?(booth.store_id)
        else
          BoothCast.exists?(cast_user_id: current_user.id, booth_id: booth.id)
        end

      unless allowed
        head :forbidden
        return
      end

      @booth = booth
    end

    def authorize_update!
      policy = Authorization::BoothPolicy.new(current_user, @booth)
      head :forbidden unless policy.update?
    end

    def check_selected_booth!
      key = action_name == "update" ? "booth_edit" : "booth_#{action_name}"
      require_selected_booth!(@booth, return_to_key: key)
    end

    def render_selection_conflict_form(message)
      @booth.assign_attributes(params.fetch(:booth, {}).permit(:name, :description))
      @booth.errors.add(:base, message)
      load_cast_memberships_for_booth if current_user.at_least?(:store_admin)
      render :edit, status: :conflict
    end

    def booth_params
      params.require(:booth).permit(:name, :description, :thumbnail_image, :remove_thumbnail_image)
    end

    def respond_booth_update_error(
      messages,
      status: :unprocessable_entity,
      code: "booth_update_invalid",
      retryable: false
    )
      message = messages.join(" / ")

      respond_to do |format|
        format.turbo_stream do
          flash.now[:alert] = message

          render turbo_stream: turbo_stream.update(
            "flash_inner",
            partial: "shared/flash_message",
            locals: { level: "danger", message: flash.now[:alert] }
          ), status: :unprocessable_entity
        end

        format.html do
          redirect_to edit_cast_booth_path(@booth), alert: message
        end

        format.json do
          render json: { error: code, message:, retryable: }, status:
        end
      end
    end

    def set_booth_for_show
      booth = Booth.find(params[:id])

      allowed =
        if current_user.system_admin?
          true
        elsif current_user.at_least?(:store_admin)
          current_user.admin_of_store?(booth.store_id)
        else
          BoothCast.exists?(cast_user_id: current_user.id, booth_id: booth.id)
        end

      unless allowed
        head :forbidden
        return
      end

      @booth = booth
    end

    def load_cast_memberships_for_booth
      @cast_memberships =
        StoreMembership
          .includes(:user)
          .where(store_id: @booth.store_id, membership_role: :cast)
          .order(:id)
    end

    def create_initial_booth_cast_if_requested(booth)
      cast_user_id = requested_booth_cast_user_id
      return true if cast_user_id.blank?

      unless current_user.at_least?(:store_admin)
        booth.errors.add(:base, "キャストを紐づける権限がありません")
        return false
      end

      if booth.booth_casts.exists?
        booth.errors.add(:base, "このブースには既にキャストが紐づいています（Phase1では差し替えできません）")
        return false
      end

      unless StoreMembership.exists?(store_id: booth.store_id, membership_role: :cast, user_id: cast_user_id)
        booth.errors.add(:base, "選択できないキャストです")
        return false
      end

      BoothCast.create!(booth: booth, cast_user_id: cast_user_id)
      true
    rescue ActiveRecord::RecordInvalid => e
      e.record.errors.full_messages.each { |message| booth.errors.add(:base, message) }
      false
    end

    def requested_booth_cast_user_id
      params.fetch(:booth_cast, {}).permit(:cast_user_id)[:cast_user_id].presence
    end
  end
end
