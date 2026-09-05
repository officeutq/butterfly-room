# frozen_string_literal: true

module ImageAttachments
  # Validates multipart images, stages their Blob objects outside a DB
  # transaction, and hands ownership to StagedPairUpdateService for one atomic
  # model update.
  class MultipartUpdateService
    class Error < StandardError; end

    def initialize(
      record:,
      purpose:,
      payload:,
      attributes: {},
      blob_upload_service: StagedBlobUploadService,
      pair_update_service: StagedPairUpdateService
    )
      @record = record
      @purpose_name = purpose
      @purpose = record.image_attachment_purpose_for(purpose)
      @payload = payload.is_a?(MultipartPayload) ? payload.validate! : MultipartPayload.parse(payload)
      @attributes = attributes.to_h
      @blob_upload_service = blob_upload_service
      @pair_update_service = pair_update_service
      @staged_blobs = {}
      @called = false
    end

    def call(&block)
      raise Error, "service instances cannot be reused" if @called

      @called = true
      crop_data = validate_payload_images!
      stage_required_blobs!
      updater = build_pair_updater(crop_data)

      # From this point StagedPairUpdateService owns failure cleanup.
      @staged_blobs.clear
      updater.call(&block)
    ensure
      cleanup_staged_blobs
    end

    private

    def validate_payload_images!
      validator = PairValidator.new(purpose: @purpose)
      case @payload.operation
      when :replace
        validator.call(
          source: @payload.source_upload,
          display: @payload.display_upload,
          crop_data: @payload.crop_data
        ).crop_data
      when :reedit
        crop_data = validator.crop_data!(@payload.crop_data)
        validator.image!(@payload.display_upload, role: :display, crop_data:)
        crop_data
      when :delete
        nil
      end
    end

    def stage_required_blobs!
      if @payload.operation == :replace
        @staged_blobs[:source] = stage_blob(:source, @payload.source_upload)
      end
      unless @payload.operation == :delete
        @staged_blobs[:display] = stage_blob(:display, @payload.display_upload)
      end
    end

    def stage_blob(role, upload)
      @blob_upload_service.new(
        record: @record,
        purpose: @purpose_name,
        role:,
        upload:
      ).call
    end

    def build_pair_updater(crop_data)
      @pair_update_service.new(
        record: @record,
        purpose: @purpose_name,
        operation: @payload.operation,
        expected_snapshot: @payload.expected_snapshot,
        attributes: @attributes,
        crop_data:,
        new_source_blob: @staged_blobs[:source],
        new_display_blob: @staged_blobs[:display]
      )
    end

    def cleanup_staged_blobs
      @staged_blobs.values.uniq(&:id).each do |blob|
        StagedBlobPurgeService.new(blob:).call if blob.persisted?
      rescue StandardError => error
        Rails.logger.error(
          "[ImageAttachments::MultipartUpdateService] staged blob cleanup failed " \
          "blob=#{blob.id} error=#{error.class.name}"
        )
      end
      @staged_blobs.clear
    end
  end
end
