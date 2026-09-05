# frozen_string_literal: true

module Booths
  class UpdateService
    class Error < StandardError; end
    class StaleImageError < Error; end
    class ImageUploadError < Error; end

    def initialize(
      booth:,
      attributes:,
      image_update: nil,
      legacy_thumbnail_upload: nil,
      remove_legacy_thumbnail: false,
      multipart_update_service: ImageAttachments::MultipartUpdateService,
      legacy_update_service: ImageAttachments::UpdateService
    )
      @booth = booth
      @attributes = attributes.to_h.symbolize_keys
      @image_update = image_update
      @legacy_thumbnail_upload = legacy_thumbnail_upload
      @remove_legacy_thumbnail = ActiveModel::Type::Boolean.new.cast(remove_legacy_thumbnail)
      @multipart_update_service = multipart_update_service
      @legacy_update_service = legacy_update_service

      validate_contract!
    end

    def call(&block)
      if @image_update
        update_image_pair(&block)
      else
        update_legacy_thumbnail(&block)
      end
    rescue ImageAttachments::UpdateService::Error,
           ImageAttachments::MultipartUpdateService::Error,
           ImageAttachments::PairValidator::Invalid,
           ImageAttachments::StagedBlobUploadService::UploadFailedError,
           ImageAttachments::StagedPairUpdateService::Error => error
      retain_attributes_for_errors
      @booth.errors.add(:base, error_message(error)) if @booth.errors.empty?
      raise wrapped_error_class(error), error.message
    end

    private

    def validate_contract!
      return unless @image_update && (@legacy_thumbnail_upload.present? || @remove_legacy_thumbnail)

      @booth.errors.add(:base, "新旧の画像更新を同時に送信できません。画面を再読み込みしてください。")
      raise Error, "legacy thumbnail and image pair updates cannot be combined"
    end

    def update_image_pair(&block)
      @multipart_update_service.new(
        record: @booth,
        purpose: :thumbnail,
        payload: @image_update,
        attributes: @attributes
      ).call(&block)
    end

    def update_legacy_thumbnail(&block)
      @legacy_update_service.new(
        record: @booth,
        attachment_name: :thumbnail_image,
        attributes: @attributes,
        upload: @legacy_thumbnail_upload,
        remove_attachment: @remove_legacy_thumbnail,
        max_width: 1920,
        max_height: 1080
      ).call(&block)
    end

    def retain_attributes_for_errors
      @booth.assign_attributes(@attributes)
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
