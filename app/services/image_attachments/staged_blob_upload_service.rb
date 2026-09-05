# frozen_string_literal: true

module ImageAttachments
  # Uploads one validated multipart tempfile as an owned, expiring staged Blob.
  # The metadata is persisted before external storage IO so the cleanup job can
  # recover a process interruption between the DB write and pair commit.
  class StagedBlobUploadService
    class UploadFailedError < StandardError; end

    def initialize(record:, purpose:, role:, upload:)
      @record = record
      @purpose = record.image_attachment_purpose_for(purpose)
      @role = role.to_sym
      @upload = upload
      validate_contract!
    end

    def call
      file = @upload.tempfile
      file.rewind
      blob = ActiveStorage::Blob.build_after_unfurling(
        io: file,
        filename: "#{@role}.jpg",
        content_type: PairValidator::JPEG_CONTENT_TYPE,
        metadata: StagedBlobMetadata.build(
          existing_metadata: { identified: true },
          purpose: @purpose,
          role: @role
        ),
        service_name: attachment_service_name,
        identify: false,
        record: @record
      )
      blob.save!
      file.rewind
      blob.upload_without_unfurling(file)
      unless blob.service.exist?(blob.key)
        raise UploadFailedError, "保存先で画像を確認できませんでした。"
      end

      blob
    rescue StandardError => error
      cleanup(blob) if defined?(blob) && blob
      raise if error.is_a?(UploadFailedError)

      Rails.logger.warn(
        "[ImageAttachments::StagedBlobUploadService] upload failed " \
        "record=#{@record.class.name}:#{@record.id || "new"} purpose=#{@purpose.name} " \
        "role=#{@role} error=#{error.class.name}"
      )
      raise UploadFailedError, "画像を保存できませんでした。再度保存してください。"
    end

    private

    def validate_contract!
      raise ArgumentError, "role must be source or display" unless %i[source display].include?(@role)
      unless @upload.respond_to?(:tempfile) && @upload.tempfile.respond_to?(:rewind)
        raise ArgumentError, "upload must provide a rewindable tempfile"
      end
    end

    def attachment_service_name
      attachment_name = @role == :source ? @purpose.source_attachment : @purpose.display_attachment
      reflection = @record.class.attachment_reflections.fetch(attachment_name.to_s)
      name = reflection.options[:service_name]
      name = name.call(@record) if name.respond_to?(:call)
      (name || ActiveStorage::Blob.service.name).to_s
    rescue KeyError
      raise ArgumentError, "unknown image attachment"
    end

    def cleanup(blob)
      return unless blob.persisted? && StagedBlobMetadata.owned?(blob)

      StagedBlobPurgeService.new(blob:).call
    rescue StandardError => error
      Rails.logger.error(
        "[ImageAttachments::StagedBlobUploadService] staged blob cleanup failed " \
        "blob=#{blob.id} error=#{error.class.name}"
      )
    end
  end
end
