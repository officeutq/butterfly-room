# frozen_string_literal: true

module Admin
  class BoothsController < Admin::BaseController
    before_action :require_current_store!, only: %i[watch]
    before_action :set_booth, only: %i[show edit update watch]
    before_action :authorize_update!, only: %i[edit update]

    def index
      render plain: "admin booths index (stub)"
    end

    def show
    end

    def edit
    end

    def update
      if remove_thumbnail_image?
        @booth.thumbnail_image.purge_later if @booth.thumbnail_image.attached?
      end

      if @booth.update(booth_params)
        redirect_to admin_booth_path(@booth), notice: "更新しました"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def watch
      policy = Authorization::BoothPolicy.new(current_user, @booth)
      head :forbidden and return unless policy.admin_operate?

      stream_session = StreamSession.find_by(id: @booth.current_stream_session_id)

      if stream_session.blank? || !stream_session.live?
        redirect_to admin_booth_path(@booth), alert: "配信中ではありません"
        return
      end

      redirect_to booth_path(@booth)
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
