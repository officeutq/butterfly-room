# frozen_string_literal: true

module ImageAttachments
  class RemediateService
    ELIGIBLE_STATUSES = %w[needs_normalization metadata_mismatch].freeze

    Upload = Data.define(:tempfile, :original_filename)
    Result = Data.define(
      :dry_run,
      :status,
      :record_type,
      :record_id,
      :attachment_name,
      :expected_attachment_id,
      :expected_blob_id,
      :attachment_id,
      :blob_id,
      :filename,
      :content_type,
      :actual_format,
      :stored,
      :convertible
    )

    class Error < StandardError; end
    class TargetNotFoundError < Error; end
    class StaleTargetError < Error; end
    class NotRemediableError < Error; end
    class ApplyFailedError < Error; end

    def initialize(
      record_type:,
      record_id:,
      attachment_name:,
      expected_attachment_id:,
      expected_blob_id:,
      apply: false
    )
      @record_type = normalize_record_type(record_type)
      @record_id = positive_integer!(record_id, :record_id)
      @attachment_name = normalize_attachment_name(attachment_name)
      @expected_attachment_id = positive_integer!(expected_attachment_id, :expected_attachment_id)
      @expected_blob_id = positive_integer!(expected_blob_id, :expected_blob_id)
      @apply = ActiveModel::Type::Boolean.new.cast(apply)

      validate_target_pair!
    end

    def call
      # JSON結果へS3キーを含むActive Storage内部ログを混在させない。
      Rails.logger.silence(Logger::UNKNOWN) { call_without_logging }
    end

    private

    def call_without_logging
      record = find_record
      entry = inspect_current_attachment(record)

      unless expected_target?(entry)
        return result_for(entry, status: "skipped_already_normalized") if entry.status == "ok"

        raise StaleTargetError, "attachment or blob changed after inventory"
      end

      return result_for(entry, status: "skipped_already_normalized") if entry.status == "ok"
      unless ELIGIBLE_STATUSES.include?(entry.status)
        raise NotRemediableError, "attachment is not safely remediable (status=#{entry.status})"
      end
      return result_for(entry, status: "eligible") unless @apply

      replace_attachment(record, entry)
    end

    def find_record
      @record_type.constantize.find(@record_id)
    rescue ActiveRecord::RecordNotFound
      raise TargetNotFoundError, "target record was not found"
    end

    def inspect_current_attachment(record)
      result = InventoryService.new(
        inspect_all: true,
        limit: 1,
        record_type: @record_type,
        record_id: record.id
      ).call
      entry = result.entries.first
      raise TargetNotFoundError, "target attachment was not found" unless entry

      entry
    end

    def expected_target?(entry)
      entry.attachment_id == @expected_attachment_id && entry.blob_id == @expected_blob_id
    end

    def replace_attachment(record, entry)
      attachment = record.public_send(@attachment_name)
      max_width, max_height = target_dimensions

      attachment.blob.open do |file|
        upload = Upload.new(tempfile: file, original_filename: attachment.filename.to_s)
        UpdateService.new(
          record:,
          attachment_name: @attachment_name,
          attributes: {},
          upload:,
          remove_attachment: false,
          max_width:,
          max_height:,
          expected_attachment_id: @expected_attachment_id,
          expected_blob_id: @expected_blob_id
        ).call
      end

      normalized_entry = inspect_current_attachment(record.reload)
      unless normalized_entry.status == "ok"
        raise NotRemediableError, "normalized attachment verification failed"
      end

      result_for(
        normalized_entry,
        status: "normalized",
        expected_attachment_id: entry.attachment_id,
        expected_blob_id: entry.blob_id
      )
    rescue UpdateService::StaleAttachmentError
      raise StaleTargetError, "attachment or blob changed after inventory"
    rescue ActiveStorage::FileNotFoundError, UpdateService::Error, ActiveRecord::ActiveRecordError => error
      raise ApplyFailedError, "remediation failed (#{error.class.name})"
    end

    def result_for(
      entry,
      status:,
      expected_attachment_id: @expected_attachment_id,
      expected_blob_id: @expected_blob_id
    )
      Result.new(
        dry_run: !@apply,
        status:,
        record_type: @record_type,
        record_id: @record_id,
        attachment_name: @attachment_name,
        expected_attachment_id:,
        expected_blob_id:,
        attachment_id: entry.attachment_id,
        blob_id: entry.blob_id,
        filename: entry.filename,
        content_type: entry.content_type,
        actual_format: entry.actual_format,
        stored: entry.stored,
        convertible: entry.convertible
      )
    end

    def target_dimensions
      InventoryService::TARGET_ATTACHMENTS.fetch(@record_type).fetch(@attachment_name)
    end

    def normalize_record_type(value)
      value.to_s.strip
    end

    def normalize_attachment_name(value)
      value.to_s.strip
    end

    def validate_target_pair!
      attachments = InventoryService::TARGET_ATTACHMENTS[@record_type]
      return if attachments&.key?(@attachment_name)

      raise ArgumentError, "record_type and attachment_name must identify a supported display image"
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
