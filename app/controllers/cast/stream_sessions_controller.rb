# frozen_string_literal: true

module Cast
  class StreamSessionsController < Cast::BaseController
    before_action :set_stream_session, only: %i[show finish pending_drink_orders meta_display metadata start_broadcast]
    before_action :authorize_stream_session_access!, only: %i[show finish pending_drink_orders meta_display metadata start_broadcast]

    def show
      booth = @stream_session.booth

      unless @stream_session.ended?
        redirect_to live_cast_booth_path(booth), alert: "終了済み配信のリザルトのみ表示できます"
        return
      end

      comments_scope = Comment.alive.where(stream_session_id: @stream_session.id)
      drink_orders_scope = DrinkOrder.where(stream_session_id: @stream_session.id)
      consumed_orders_scope = drink_orders_scope.consumed
      refunded_orders_scope = drink_orders_scope.refunded
      presences_scope = Presence.where(stream_session_id: @stream_session.id)
      ledger_scope = StoreLedgerEntry.where(stream_session_id: @stream_session.id)

      refunded_order_ids = refunded_orders_scope.pluck(:id)
      refund_points_scope =
        WalletTransaction.where(
          kind: :release,
          ref_type: "DrinkOrder",
          ref_id: refunded_order_ids
        )

      @booth = booth
      @cast_user = @stream_session.started_by_cast_user

      @comment_count = comments_scope.count
      @viewer_count = presences_scope.distinct.count(:customer_user_id)

      @drink_order_count = drink_orders_scope.count
      @consumed_drink_count = consumed_orders_scope.count
      @refunded_drink_count = refunded_orders_scope.count

      @consumed_points = ledger_scope.sum(:points)
      @refunded_points = refund_points_scope.sum(:points)

      @avg_consumed_points =
        if @consumed_drink_count.positive?
          (@consumed_points.to_f / @consumed_drink_count).round(1)
        else
          0
        end

      @avg_refunded_points =
        if @refunded_drink_count.positive?
          (@refunded_points.to_f / @refunded_drink_count).round(1)
        else
          0
        end

      @started_at = @stream_session.broadcast_started_at
      @ended_at = @stream_session.ended_at
      @duration_seconds =
        if @started_at.present? && @ended_at.present? && @ended_at >= @started_at
          (@ended_at - @started_at).to_i
        else
          0
        end
    end

    def finish
      ended_session = StreamSessions::EndService.new(
        stream_session: @stream_session,
        actor: current_user
      ).call

      redirect_to cast_stream_session_path(ended_session),
                  notice: "今回の配信が終了しました"
    rescue => e
      redirect_to live_cast_booth_path(@stream_session.booth_id), alert: e.message
    end

    def pending_drink_orders
      render partial: "cast/stream_sessions/pending_drink_orders",
             locals: { stream_session: @stream_session }
    end

    def meta_display
      booth = @stream_session.booth

      unless booth.current_stream_session_id == @stream_session.id
        return head :forbidden
      end

      @booth = booth
    end

    # PATCH /cast/stream_sessions/:id/metadata
    def metadata
      booth = @stream_session.booth

      unless booth.current_stream_session_id == @stream_session.id
        return head :forbidden
      end

      unless booth.standby?
        return respond_conflict(booth, "スタンバイ中のみ編集できます")
      end

      @stream_session.update!(metadata_params)

      StreamSessionNotifier.broadcast_stream_state(booth: booth)

      respond_to do |format|
        format.html do
          redirect_to live_cast_booth_path(booth)
        end

        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "stream_meta_display",
            partial: "cast/stream_sessions/meta_display_frame",
            locals: { booth: booth, stream_session: @stream_session }
          )
        end

        format.json { render json: { ok: true }, status: :ok }
        format.any { head :ok }
      end
    rescue ActiveRecord::RecordInvalid => e
      message = e.record.errors.full_messages.join(", ").presence || "入力に誤りがあります"

      respond_to do |format|
        format.html { redirect_to live_cast_booth_path(booth), alert: message }
        format.turbo_stream do
          render turbo_stream: turbo_stream.append(
            "flash_inner",
            partial: "shared/flash_message",
            locals: { level: "danger", message: message }
          ), status: :unprocessable_entity
        end
        format.json { render json: { error: message }, status: :unprocessable_entity }
        format.any { render plain: message, status: :unprocessable_entity }
      end
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end

    def start_broadcast
      booth = @stream_session.booth

      unless booth.current_stream_session_id == @stream_session.id
        return head :forbidden
      end

      if @stream_session.broadcast_started_at.blank?
        @stream_session.update!(broadcast_started_at: Time.current)
      end

      render json: { ok: true }, status: :ok
    rescue ActiveRecord::RecordInvalid => e
      message = e.record.errors.full_messages.join(", ").presence || "配信開始時刻の保存に失敗しました"
      render json: { error: message }, status: :unprocessable_entity
    end

    private

    def set_stream_session
      @stream_session = StreamSession.find(params[:id])
    end

    def authorize_stream_session_access!
      return if operable_booth_for_stream_session?(@stream_session.booth)

      session.delete(:current_booth_id)
      head :forbidden
    end

    def metadata_params
      params.require(:stream_session).permit(:title)
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
