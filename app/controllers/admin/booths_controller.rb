# frozen_string_literal: true

module Admin
  class BoothsController < Admin::BaseController
    include RemovableImageAttachment
    include AttachmentPersistenceChecker

    before_action :require_current_store!
    before_action :set_booth, only: %i[show edit update watch archive force_end]
    before_action :authorize_update!, only: %i[edit update]

    def index
      @include_archived = ActiveModel::Type::Boolean.new.cast(params[:archived])

      scope = current_store.booths
      scope = scope.active unless @include_archived

      @booths = scope.order(id: :desc)
    end

    def show
    end

    def new
      @booth = current_store.booths.new
      authorize_create!
    end

    def create
      @booth = current_store.booths.new
      authorize_create!

      @booth.assign_attributes(booth_create_params)

      Booth.transaction do
        @booth.save!
        Booths::ProvisionIvsStageService.new(booth: @booth).call!
      end

      unless ensure_attachment_persisted!(record: @booth, attachment_name: :thumbnail_image)
        return render :new, status: :unprocessable_entity
      end

      purge_attachment_if_requested(
        record: @booth,
        attachment_name: :thumbnail_image,
        remove_param_name: :remove_thumbnail_image
      )

      redirect_to admin_booth_path(@booth), notice: "ブースを作成しました"

    rescue ActiveRecord::RecordInvalid
      render :new, status: :unprocessable_entity

    rescue Booths::ProvisionIvsStageService::StageProvisionFailed => e
      @booth.errors.add(:base, "IVS Stage の作成に失敗しました: #{e.message}")
      render :new, status: :unprocessable_entity

    rescue NormalizedImageAttachment::InvalidImageAttachment => e
      Rails.logger.error("[BoothCreate] #{e.class}: #{e.message}")

      @booth ||= current_store.booths.new
      @booth.assign_attributes(booth_create_params.except(:thumbnail_image))
      @booth.errors.add(:thumbnail_image, e.message)

      render :new, status: :unprocessable_entity

    rescue => e
      Rails.logger.error("[BoothCreate] #{e.class}: #{e.message}")

      @booth ||= current_store.booths.new
      @booth.errors.add(:base, "ブースの作成に失敗しました")

      render :new, status: :unprocessable_entity
    end

    def edit
    end

    def update
      begin
        if @booth.update(booth_params)
          unless ensure_attachment_persisted!(record: @booth, attachment_name: :thumbnail_image)
            return render :edit, status: :unprocessable_entity
          end

          purge_attachment_if_requested(
            record: @booth,
            attachment_name: :thumbnail_image,
            remove_param_name: :remove_thumbnail_image
          )

          redirect_to admin_booth_path(@booth), notice: "更新しました"
        else
          render :edit, status: :unprocessable_entity
        end

      rescue => e
        Rails.logger.error("[BoothUpdate] #{e.class}: #{e.message}")

        @booth.errors.add(:thumbnail_image, "の処理に失敗しました。png / jpg / webp の画像で再度お試しください")

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

    # 配信の強制終了
    def force_end
      policy = Authorization::BoothPolicy.new(current_user, @booth)
      head :forbidden and return unless policy.admin_operate?

      stream_session = StreamSession.find_by(id: @booth.current_stream_session_id)
      if stream_session.blank?
        redirect_to admin_booth_path(@booth), alert: "配信セッションが見つかりません（既に終了済みの可能性があります）"
        return
      end

      StreamSessions::ForceEndService.new(stream_session: stream_session, actor: current_user).call
      redirect_to admin_booth_path(@booth), notice: "配信を強制終了しました"
    rescue StreamSessions::EndService::AlreadyEnded
      redirect_to admin_booth_path(@booth), alert: "既に配信は終了しています"
    rescue StreamSessions::EndService::NotAuthorized
      head :forbidden
    rescue => e
      redirect_to admin_booth_path(@booth), alert: e.message
    end

    def archive
      policy = Authorization::BoothPolicy.new(current_user, @booth)
      head :forbidden and return unless policy.update?

      booth = Booth.lock.find(@booth.id)

      if !booth.offline? || booth.current_stream_session_id.present?
        redirect_to admin_booths_path,
                    alert: "ブース##{booth.id}（#{booth.name}）は配信中の可能性があるためアーカイブできません。先に配信を終了してください。"
        return
      end

      booth.update!(archived_at: Time.current)

      redirect_to admin_booths_path, notice: "ブースをアーカイブしました"
    end

    private

    def set_booth
      scope =
        if current_user.system_admin?
          Booth.all
        else
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

    def booth_create_params
      params.require(:booth).permit(:name, :description, :thumbnail_image)
    end

    def booth_params
      params.require(:booth).permit(:description, :thumbnail_image)
    end
  end
end
