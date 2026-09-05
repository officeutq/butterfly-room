# frozen_string_literal: true

module Profiles
  class UpdateService
    PURPOSES = %i[avatar cover].freeze

    class Error < StandardError; end

    def initialize(
      user:,
      attributes:,
      image_updates: {},
      legacy_avatar_upload: nil,
      remove_legacy_avatar: false,
      multipart_update_service: ImageAttachments::MultipartUpdateService,
      legacy_update_service: ImageAttachments::UpdateService
    )
      @user = user
      @attributes = attributes.to_h.symbolize_keys
      @image_updates = image_updates.to_h.symbolize_keys
      @legacy_avatar_upload = legacy_avatar_upload
      @remove_legacy_avatar = ActiveModel::Type::Boolean.new.cast(remove_legacy_avatar)
      @multipart_update_service = multipart_update_service
      @legacy_update_service = legacy_update_service

      validate_contract!
    end

    def call(&block)
      if @image_updates.any?
        update_image_pairs(&block)
      elsif @legacy_avatar_upload.present? || @remove_legacy_avatar
        update_legacy_avatar(&block)
      else
        update_attributes(&block)
      end
    rescue ImageAttachments::UpdateService::Error,
           ImageAttachments::MultipartUpdateService::Error,
           ImageAttachments::PairValidator::Invalid,
           ImageAttachments::StagedBlobUploadService::UploadFailedError,
           ImageAttachments::StagedPairUpdateService::Error => error
      retain_attributes_for_errors
      @user.errors.add(:base, error_message(error)) if @user.errors.empty?
      raise Error, error.message
    end

    private

    def validate_contract!
      unknown = @image_updates.keys - PURPOSES
      raise ArgumentError, "unknown user image purpose: #{unknown.first}" if unknown.any?

      return unless @image_updates.any? && (@legacy_avatar_upload.present? || @remove_legacy_avatar)

      @user.errors.add(:base, "新旧の画像更新を同時に送信できません。画面を再読み込みしてください。")
      raise Error, "legacy avatar and image pair updates cannot be combined"
    end

    def update_image_pairs(&block)
      @multipart_update_service.new(
        record: @user,
        updates: @image_updates,
        attributes: @attributes
      ).call(&block)
    end

    def update_legacy_avatar(&block)
      @legacy_update_service.new(
        record: @user,
        attachment_name: :avatar,
        attributes: @attributes,
        upload: @legacy_avatar_upload,
        remove_attachment: @remove_legacy_avatar,
        max_width: 1024,
        max_height: 1024
      ).call(&block)
    end

    def update_attributes
      @user.class.transaction do
        @user.update!(@attributes)
        yield @user if block_given?
      end
      @user
    end

    def retain_attributes_for_errors
      @user.assign_attributes(@attributes)
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
  end
end
