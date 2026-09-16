# frozen_string_literal: true

module Stores
  class UpdateService
    class Error < StandardError; end
    class StaleImageError < Error; end
    class ImageUploadError < Error; end
    class UnpublishBlocked < Error; end

    def initialize(
      store:,
      attributes:,
      actor_user: nil,
      source: "application",
      request_id: nil,
      image_update: nil,
      legacy_thumbnail_upload: nil,
      remove_legacy_thumbnail: false,
      multipart_update_service: ImageAttachments::MultipartUpdateService,
      legacy_update_service: ImageAttachments::UpdateService
    )
      @store = store
      @attributes = attributes.to_h.symbolize_keys
      @change_tracker = Logs::ChangeTracker.new(actor_user:, source:, request_id:)
      @image_update = image_update
      @legacy_thumbnail_upload = legacy_thumbnail_upload
      @remove_legacy_thumbnail = ActiveModel::Type::Boolean.new.cast(remove_legacy_thumbnail)
      @multipart_update_service = multipart_update_service
      @legacy_update_service = legacy_update_service

      validate_contract!
    end

    def call(&block)
      record_change = proc do |record|
        block&.call(record)
        @change_tracker.record!(record)
      end
      if @image_update
        update_image_pair(&record_change)
      else
        update_legacy_thumbnail(&record_change)
      end
    rescue UnpublishBlocked
      retain_attributes_for_errors
      raise
    rescue ImageAttachments::UpdateService::Error,
           ImageAttachments::MultipartUpdateService::Error,
           ImageAttachments::PairValidator::Invalid,
           ImageAttachments::StagedBlobUploadService::UploadFailedError,
           ImageAttachments::StagedPairUpdateService::Error => error
      retain_attributes_for_errors
      @store.errors.add(:base, error_message(error)) if @store.errors.empty?
      raise wrapped_error_class(error), error.message
    end

    private

    def validate_contract!
      return unless @image_update && (@legacy_thumbnail_upload.present? || @remove_legacy_thumbnail)

      @store.errors.add(:base, "新旧の画像更新を同時に送信できません。画面を再読み込みしてください。")
      raise Error, "legacy thumbnail and image pair updates cannot be combined"
    end

    def update_image_pair(&block)
      @multipart_update_service.new(
        record: @store,
        purpose: :thumbnail,
        payload: @image_update,
        attributes: @attributes,
        before_save: method(:before_store_save)
      ).call(&block)
    end

    def update_legacy_thumbnail(&block)
      @legacy_update_service.new(
        record: @store,
        attachment_name: :thumbnail,
        attributes: @attributes,
        upload: @legacy_thumbnail_upload,
        remove_attachment: @remove_legacy_thumbnail,
        max_width: 1920,
        max_height: 1080,
        before_save: method(:before_store_save)
      ).call(&block)
    end

    # 画像の有無にかかわらず、更新側が店舗をロックした後・同じtransaction内で判定する。
    # 配信側は店舗の共有ロックを先に取るため、発行途中の接続を見落とさない。
    def before_store_save(store)
      @change_tracker.capture_before(store)
      return unless store.published? && @attributes.key?(:published) &&
        ActiveModel::Type::Boolean.new.cast(@attributes[:published]) == false

      booth_ids = store.booths.select(:id)
      broadcasting = store.booths.where(status: %i[live away]).exists? ||
        StreamSession.where(store_id: store.id, status: :live, ended_at: nil).where.not(broadcast_started_at: nil).exists?
      starting = StreamPublisherConnection.unreleased.joins(:stream_session)
        .where(booth_id: booth_ids, stream_sessions: { status: :live, ended_at: nil }).exists?
      return unless broadcasting || starting

      message = "配信中・離席中、または配信開始処理中のブースがあります。配信を終了するか開始を取り消してから非公開にしてください"
      store.errors.add(:base, message)
      raise UnpublishBlocked, message
    end

    def retain_attributes_for_errors
      @store.assign_attributes(@attributes)
    end

    def error_message(error)
      case error
      when ImageAttachments::StagedPairUpdateService::StalePairError
        "画像が別の操作で更新されました。画面を再読み込みしてやり直してください。"
      when ImageAttachments::StagedBlobUploadService::UploadFailedError
        "画像を保存できませんでした。再度保存してください。"
      else
        error.message
      end
    end

    def wrapped_error_class(error)
      case error
      when ImageAttachments::StagedPairUpdateService::StalePairError
        StaleImageError
      when ImageAttachments::StagedBlobUploadService::UploadFailedError
        ImageUploadError
      else
        Error
      end
    end
  end
end
