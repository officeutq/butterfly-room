# frozen_string_literal: true

module Cast
  class StreamSessionsController < Cast::BaseController
    def finish
      session = StreamSession.find(params[:id])

      StreamSessions::EndService.new(
        stream_session: session,
        actor: current_user
      ).call

      redirect_to cast_booth_path(session.booth_id), notice: "スタンバイを終了しました"
    rescue => e
      redirect_to cast_booth_path(session.booth_id), alert: e.message
    end

    def pending_drink_orders
      stream_session = StreamSession.find(params[:id])

      render partial: "cast/stream_sessions/pending_drink_orders",
             locals: { stream_session: stream_session }
    end

    def meta_modal
      stream_session = StreamSession.find(params[:id])
      booth = stream_session.booth

      unless booth.current_stream_session_id == stream_session.id
        return head :forbidden
      end

      unless operable_booth_for_stream_session?(booth)
        return head :forbidden
      end

      unless booth.standby?
        return head :conflict
      end

      render partial: "cast/stream_sessions/meta_modal",
             locals: { booth: booth, stream_session: stream_session }
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end

    # PATCH /cast/stream_sessions/:id/metadata
    def metadata
      stream_session = StreamSession.find(params[:id])
      booth = stream_session.booth

      # 必須: current session 一致
      unless booth.current_stream_session_id == stream_session.id
        return head :forbidden
      end

      # 認可: StartService と同等
      unless operable_booth_for_stream_session?(booth)
        return head :forbidden
      end

      # 状態ガード: standby のみ許可
      unless booth.standby?
        return respond_conflict(booth, "スタンバイ中のみ編集できます")
      end

      stream_session.update!(metadata_params)

      # viewer 側に即反映（booth:stream_state 購読に乗せる）
      StreamSessionNotifier.broadcast_stream_state(booth: booth)

      respond_to do |format|
        format.html do
          redirect_to live_cast_booth_path(booth), notice: "設定しました"
        end

        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.append(
              "flash_inner",
              partial: "shared/flash_message",
              locals: { level: "success", message: "設定しました" }
            )
          ]
        end

        format.json { render json: { ok: true }, status: :ok }
        format.any { head :ok }
      end
    rescue ActiveRecord::RecordInvalid => e
      message = e.record.errors.full_messages.join(", ").presence || "入力に誤りがあります"

      respond_to do |format|
        format.html { redirect_to live_cast_booth_path(booth), alert: message }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(
              "modal",
              partial: "cast/stream_sessions/meta_modal",
              locals: { booth: booth, stream_session: e.record }
            ),
            turbo_stream.append(
              "flash_inner",
              partial: "shared/flash_message",
              locals: { level: "danger", message: message }
            )
          ], status: :unprocessable_entity
        end
        format.json { render json: { error: message }, status: :unprocessable_entity }
        format.any { render plain: message, status: :unprocessable_entity }
      end
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end

    private

    def metadata_params
      params.require(:stream_session).permit(:title, :description)
    end

    def operable_booth_for_stream_session?(booth)
      actor = current_user

      return false if actor.blank?
      return true if actor.system_admin?

      if actor.at_least?(:store_admin)
        return actor.admin_of_store?(booth.store_id)
      end

      BoothCast.exists?(cast_user_id: actor.id, booth_id: booth.id)
    end

    def respond_conflict(booth, message)
      respond_to do |format|
        format.html { redirect_to live_cast_booth_path(booth), alert: message }
        format.turbo_stream do
          render turbo_stream: turbo_stream.append(
            "flash_inner",
            partial: "shared/flash_message",
            locals: { level: "danger", message: message }
          ), status: :conflict
        end
        format.json { render json: { error: message }, status: :conflict }
        format.any { render plain: message, status: :conflict }
      end
    end
  end
end
