# frozen_string_literal: true

module Cast
  class BoothsController < Cast::BaseController
    include RemovableImageAttachment
    include AttachmentPersistenceChecker

    before_action :set_booth, only: %i[live status edit update]
    before_action :set_booth_for_show, only: %i[show]
    before_action :authorize_update!, only: %i[edit update]

    def index
      load_selectable_booths
    end

    def show
    end

    def select_modal
      load_selectable_booths

      booth = @booths.find { |b| b.live? || b.away? }
      booth ||= @booths.first if @booths.size == 1

      if booth.present?
        result = ::Booths::EnterAsCastService.new(
          booth: booth,
          actor: current_user
        ).call

        case result.action
        when :redirect_live
          session[:current_booth_id] = result.booth.id
          session[:current_store_id] = result.booth.store_id

          redirect_path = resolve_select_modal_redirect_path(result.booth)

          if turbo_frame_request?
            flash[:notice] = "ブースを選択しました"
            render_select_modal_redirect(path: redirect_path)
          else
            redirect_to redirect_path, notice: "ブースを選択しました"
          end
        when :occupied_by_other
          if turbo_frame_request?
            flash[:alert] = "このブースはすでに配信中です"
            render_select_modal_redirect(path: cast_booths_path)
          else
            redirect_to cast_booths_path, alert: "このブースはすでに配信中です"
          end
        when :already_live_elsewhere
          if turbo_frame_request?
            flash[:alert] = "他のブースで配信中のため開始できません"
            render_select_modal_redirect(path: cast_booths_path)
          else
            redirect_to cast_booths_path, alert: "他のブースで配信中のため開始できません"
          end
        else
          if turbo_frame_request?
            flash[:alert] = "ブースを開けませんでした"
            render_select_modal_redirect(path: cast_booths_path)
          else
            redirect_to cast_booths_path, alert: "ブースを開けませんでした"
          end
        end
        return
      end

      if turbo_frame_request?
        render :select_modal, layout: false, status: :ok
      else
        redirect_to cast_booths_path(
          return_to: @return_to,
          return_to_key: @return_to_key
        )
      end
    rescue ::Booths::EnterAsCastService::NotAuthorized
      session.delete(:current_booth_id)

      if turbo_frame_request?
        flash[:alert] = "選択できないブースです"
        render_select_modal_redirect(path: cast_booths_path)
      else
        redirect_to cast_booths_path, alert: "選択できないブースです"
      end
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

      @effects = Effect.enabled_only.ordered

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
        @stream_session.started_by_cast_user_id == current_user.id &&
        (@booth.live? || @booth.away?)
    end

    def edit
    end

    def update
      success = @booth.update(booth_params)

      if success && ensure_attachment_persisted!(record: @booth, attachment_name: :thumbnail_image)
        purge_attachment_if_requested(
          record: @booth,
          attachment_name: :thumbnail_image,
          remove_param_name: :remove_thumbnail_image
        )

        redirect_path =
          if session.delete(:redirect_to_home_after_cast_booth_update)
            root_path
          else
            helpers.dashboard_path_for(current_user)
          end

        redirect_to redirect_path, notice: "ブースを更新しました"
      else
        respond_booth_update_error(@booth.errors.full_messages)
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

    def load_selectable_booths
      @include_archived = ActiveModel::Type::Boolean.new.cast(params[:archived])

      @booths =
        if current_user.system_admin?
          Booth.all
        elsif current_user.at_least?(:store_admin)
          Booth.joins(store: :store_memberships)
              .where(store_memberships: { user_id: current_user.id, membership_role: :admin })
              .distinct
        else
          Booth.joins(:booth_casts)
              .where(booth_casts: { cast_user_id: current_user.id })
              .distinct
        end

      @booths = @booths.includes(:thumbnail_image_attachment)
      @booths = @booths.active unless @include_archived
      @booths = @booths.order(Arel.sql('"booths"."archived_at" ASC NULLS FIRST'), id: :desc)

      @current_booth_id = session[:current_booth_id]
      @confirm_switch_booth = current_booth&.live? || current_booth&.away?
      @return_to = params[:return_to].presence
      @return_to_key = params[:return_to_key].presence
    end

    def render_select_modal_redirect(path:)
      @redirect_path = path
      render :select_modal_redirect, layout: false, status: :ok
    end

    def resolve_select_modal_redirect_path(booth)
      key = @return_to_key
      if key.present?
        path = resolve_return_to_key(key, booth)
        return path if path.present?
      end

      rt = safe_return_to(@return_to)
      return rt if rt.present?

      if request.referer.to_s.start_with?(cast_booths_url)
        return dashboard_path
      end

      session_rt = safe_return_to(session[:cast_return_to])
      return session_rt if session_rt.present?

      dashboard_path
    end

    def resolve_return_to_key(key, booth)
      return nil if booth.blank?

      case key.to_s
      when "booth_edit"
        edit_cast_booth_path(booth)
      when "booth_live"
        live_cast_booth_path(booth)
      else
        nil
      end
    end

    def safe_return_to(value)
      s = value.to_s
      return nil if s.blank?

      return nil unless s.start_with?("/")
      return nil if s.start_with?("//")
      return nil if s.include?("\n") || s.include?("\r")
      return nil if s.include?("\0")

      return nil if s == "/cast/current_booth"
      return nil if s == "/cast/booths/select_modal"

      s
    end

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
      params.require(:booth).permit(:name, :description, :thumbnail_image)
    end

    def respond_booth_update_error(messages)
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
        session.delete(:current_booth_id)
        head :forbidden
        return
      end

      @booth = booth
    end
  end
end
