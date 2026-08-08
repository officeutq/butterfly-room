# frozen_string_literal: true

module ImageAttachments
  class UpdateService
    class Error < StandardError; end
    class ImageProcessingError < Error; end
    class UploadFailedError < Error; end

    def initialize(
      record:,
      attachment_name:,
      attributes:,
      upload:,
      remove_attachment:,
      max_width:,
      max_height:
    )
      @record = record
      @attachment_name = attachment_name.to_sym
      @attributes = attributes.to_h.symbolize_keys
      @upload = upload
      @remove_attachment = ActiveModel::Type::Boolean.new.cast(remove_attachment)
      @max_width = positive_integer!(max_width, :max_width)
      @max_height = positive_integer!(max_height, :max_height)
      @pending_blob = nil

      validate_attachment!
      validate_attributes!
    end

    def call
      new_blob = upload? ? upload_normalized_blob : nil
      old_blob = nil
      committed = false

      @record.class.transaction do
        @record.lock! if @record.persisted? && attachment_change?
        @record.assign_attributes(@attributes)
        old_blob = current_blob if attachment_change?
        assign_attachment(new_blob)
        @record.save!
        yield @record if block_given?
      end

      committed = true
      purge_old_blob_later(old_blob)
      @pending_blob = nil
      @record
    rescue NormalizeService::InvalidImageError
      retain_attributes_for_errors
      @record.errors.add(@attachment_name, "をJPEGに変換できませんでした。別の画像を選択してください")
      raise ImageProcessingError, "image could not be normalized"
    rescue UploadFailedError
      retain_attributes_for_errors
      @record.errors.add(@attachment_name, "の保存に失敗しました。再度アップロードしてください")
      raise
    ensure
      cleanup_pending_blob unless committed
    end

    private

    def upload?
      @upload.present?
    end

    def attachment_change?
      upload? || @remove_attachment
    end

    def current_blob
      attachment = @record.public_send(@attachment_name)
      attachment.blob if attachment.attached?
    end

    def assign_attachment(new_blob)
      if new_blob.present?
        @record.public_send("#{@attachment_name}=", new_blob)
      elsif @remove_attachment
        @record.public_send("#{@attachment_name}=", nil)
      end
    end

    def upload_normalized_blob
      NormalizeService.new(
        upload: @upload,
        max_width: @max_width,
        max_height: @max_height
      ).call do |normalized|
        @pending_blob = build_blob(normalized)
        @pending_blob.save!
        normalized.io.rewind
        @pending_blob.upload_without_unfurling(normalized.io)

        unless blob_uploaded?(@pending_blob)
          raise UploadFailedError, "uploaded blob could not be found"
        end

        @pending_blob
      end
    rescue NormalizeService::InvalidImageError
      raise
    rescue UploadFailedError => error
      log_upload_failure(error)
      raise
    rescue StandardError => error
      log_upload_failure(error)
      raise UploadFailedError, "image upload failed"
    end

    def build_blob(normalized)
      ActiveStorage::Blob.build_after_unfurling(
        io: normalized.io,
        filename: normalized.filename,
        content_type: normalized.content_type,
        service_name: attachment_service_name,
        identify: false,
        record: @record
      )
    end

    def blob_uploaded?(blob)
      blob.service.exist?(blob.key)
    end

    def attachment_service_name
      service_name = attachment_reflection.options[:service_name]
      service_name = service_name.call(@record) if service_name.respond_to?(:call)
      service_name
    end

    def attachment_reflection
      @attachment_reflection ||= @record.class.attachment_reflections.fetch(@attachment_name.to_s)
    end

    def purge_old_blob_later(old_blob)
      return unless old_blob.present? && attachment_change?

      old_blob.purge_later
    rescue StandardError => error
      Rails.logger.error(
        "[ImageAttachments::UpdateService] old blob purge enqueue failed " \
        "record=#{record_log_label} attachment=#{@attachment_name} error=#{error.class.name}"
      )
    end

    def cleanup_pending_blob
      return unless @pending_blob&.persisted?

      @pending_blob.purge
    rescue StandardError => error
      Rails.logger.error(
        "[ImageAttachments::UpdateService] pending blob cleanup failed " \
        "record=#{record_log_label} attachment=#{@attachment_name} error=#{error.class.name}"
      )
    ensure
      @pending_blob = nil
    end

    def retain_attributes_for_errors
      @record.assign_attributes(@attributes)
    end

    def log_upload_failure(error)
      Rails.logger.warn(
        "[ImageAttachments::UpdateService] image upload failed " \
        "record=#{record_log_label} attachment=#{@attachment_name} error=#{error.class.name}"
      )
    end

    def record_log_label
      "#{@record.class.name}##{@record.id || "new"}"
    end

    def validate_attachment!
      attachment_reflection
    rescue KeyError
      raise ArgumentError, "unknown attachment: #{@attachment_name}"
    end

    def validate_attributes!
      return unless @attributes.key?(@attachment_name)

      raise ArgumentError, "attributes must not include #{@attachment_name}"
    end

    def positive_integer!(value, name)
      integer = Integer(value)
      raise ArgumentError, "#{name} must be positive" unless integer.positive?

      integer
    rescue TypeError, ArgumentError
      raise ArgumentError, "#{name} must be a positive integer"
    end
  end
end
