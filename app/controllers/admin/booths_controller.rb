# frozen_string_literal: true

module Admin
  class BoothsController < Admin::BaseController
    before_action :require_current_store_for_booths!
    before_action :set_booth, only: %i[show edit update watch]
    before_action :authorize_update!, only: %i[edit update]

    def index
      # current_store 配下だけ出す（店舗管理なので）
      @booths = current_store.booths.order(id: :desc)
    end

    def show
    end

    def new
      @booth = current_store.booths.new
      authorize_create!
    end

    def create
      @booth = current_store.booths.new(booth_create_params)
      authorize_create!

      Booth.transaction do
        @booth.save!
        Booths::ProvisionIvsStageService.new(booth: @booth).call!
      end

      redirect_to admin_booth_path(@booth), notice: "ブースを作成しました"
    rescue ActiveRecord::RecordInvalid
      render :new, status: :unprocessable_entity
    rescue Booths::ProvisionIvsStageService::StageProvisionFailed => e
      @booth.errors.add(:base, "IVS Stage の作成に失敗しました: #{e.message}")
      render :new, status: :unprocessable_entity
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
      scope =
        if current_user.system_admin?
          Booth.all
        else
          # require_current_store! があるので current_store は必ずいる前提
          current_store.booths
        end

      @booth = scope.find(params[:id])
    end

    def authorize_update!
      policy = Authorization::BoothPolicy.new(current_user, @booth)
      head :forbidden unless policy.update?
    end

    def authorize_create!
      policy = Authorization::BoothPolicy.new(current_user, @booth)
      head :forbidden unless policy.create?
    end

    # create 用（name など許可）
    def booth_create_params
      params.require(:booth).permit(:name, :description, :thumbnail_image)
    end

    # update 用（現状維持）
    def booth_params
      params.require(:booth).permit(:description, :thumbnail_image)
    end

    def remove_thumbnail_image?
      params.dig(:booth, :remove_thumbnail_image) == "1"
    end

    def require_current_store_for_booths!
      return if current_store.present?
      head :forbidden
    end
  end
end
