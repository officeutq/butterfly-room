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

      scope =
        current_store
          .booths
          .includes(:thumbnail_image_attachment, booth_casts: :cast_user)

      scope = scope.active unless @include_archived

      @booths = scope.order(Arel.sql('"booths"."archived_at" ASC NULLS FIRST'), id: :desc)
      @current_booth_id = session[:current_booth_id]

      @cast_memberships =
        StoreMembership
          .includes(:user)
          .where(store_id: current_store.id, membership_role: :cast)
          .order(:id)
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

      redirect_to helpers.dashboard_path_for(current_user), notice: "ブースを作成しました"

    rescue ActiveRecord::RecordInvalid
      render :new, status: :unprocessable_entity

    rescue Booths::ProvisionIvsStageService::StageProvisionFailed => e
      @booth.errors.add(:base, "IVS Stage の作成に失敗しました: #{e.message}")
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
      if @booth.update(booth_params)
        unless ensure_attachment_persisted!(record: @booth, attachment_name: :thumbnail_image)
          return render :edit, status: :unprocessable_entity
        end

        purge_attachment_if_requested(
          record: @booth,
          attachment_name: :thumbnail_image,
          remove_param_name: :remove_thumbnail_image
        )

        redirect_to helpers.dashboard_path_for(current_user), notice: "更新しました"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def assign_cast
      booth = current_store.booths.find(params[:id])

      policy = Authorization::BoothPolicy.new(current_user, booth)
      head :forbidden and return unless policy.update?

      cast_user_id = booth_cast_params[:cast_user_id]

      if booth.archived?
        redirect_to resolved_return_to, alert: "アーカイブ済みブースには紐づけできません"
        return
      end

      if booth.booth_casts.exists?
        redirect_to resolved_return_to, alert: "このブースには既にキャストが紐づいています（Phase1では差し替えできません）"
        return
      end

      unless StoreMembership.exists?(store_id: current_store.id, membership_role: :cast, user_id: cast_user_id)
        redirect_to resolved_return_to, alert: "選択できないキャストです"
        return
      end

      BoothCast.create!(booth: booth, cast_user_id: cast_user_id)

      redirect_to resolved_return_to, notice: "キャストを紐づけました"
    rescue ActionController::ParameterMissing
      redirect_to resolved_return_to, alert: "パラメータが不正です"
    rescue ActiveRecord::RecordNotFound
      head :not_found
    rescue ActiveRecord::RecordInvalid => e
      redirect_to resolved_return_to, alert: e.record.errors.full_messages.join(", ")
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

      if booth.archived?
        redirect_to admin_booths_path, alert: "ブース##{booth.id}（#{booth.name}）は既にアーカイブされています。"
        return
      end

      case booth.status.to_sym
      when :offline
        if booth.current_stream_session_id.present?
          redirect_to admin_booths_path,
                      alert: "ブース##{booth.id}（#{booth.name}）は配信セッション情報が残っているため、安全にアーカイブできません。状態を確認してください。"
          return
        end

      when :standby
        if booth.current_stream_session_id.blank?
          redirect_to admin_booths_path,
                      alert: "ブース##{booth.id}（#{booth.name}）は standby ですが配信セッション情報が見つからないため、安全にアーカイブできません。状態を確認してください。"
          return
        end

        stream_session = StreamSession.find_by(id: booth.current_stream_session_id)
        if stream_session.blank?
          redirect_to admin_booths_path,
                      alert: "ブース##{booth.id}（#{booth.name}）の配信セッションが見つからないため、安全にアーカイブできません。状態を確認してください。"
          return
        end

        StreamSessions::EndService.new(stream_session: stream_session, actor: current_user).call
        booth = Booth.lock.find(@booth.id)

        if booth.current_stream_session_id.present? || !booth.offline?
          redirect_to admin_booths_path,
                      alert: "ブース##{booth.id}（#{booth.name}）の終了処理後に状態が整わなかったため、アーカイブできませんでした。"
          return
        end

      when :live, :away
        redirect_to admin_booths_path,
                    alert: "ブース##{booth.id}（#{booth.name}）は配信中のためアーカイブできません。先に配信を終了してください。"
        return

      else
        redirect_to admin_booths_path,
                    alert: "ブース##{booth.id}（#{booth.name}）の状態を判定できないため、アーカイブできません。"
        return
      end

      booth.update!(archived_at: Time.current)

      redirect_to admin_booths_path, notice: "ブースをアーカイブしました"
    rescue StreamSessions::EndService::AlreadyEnded
      redirect_to admin_booths_path,
                  alert: "配信セッションは既に終了済みですが、状態が整っていないためアーカイブできません。状態を確認してください。"
    rescue StreamSessions::EndService::NotAuthorized
      head :forbidden
    rescue => e
      redirect_to admin_booths_path, alert: e.message
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
      params.require(:booth).permit(:name, :description, :thumbnail_image)
    end

    def booth_cast_params
      params.require(:booth_cast).permit(:cast_user_id)
    end

    def resolved_return_to
      path = params[:return_to].to_s

      return admin_booths_path if path.blank?
      return admin_booths_path unless path.start_with?("/")
      return admin_booths_path if path.start_with?("//")
      return admin_booths_path if path.include?("\n") || path.include?("\r")
      return admin_booths_path if path.include?("\0")

      path
    end
  end
end
