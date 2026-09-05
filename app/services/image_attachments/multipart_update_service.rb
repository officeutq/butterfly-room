# frozen_string_literal: true

module ImageAttachments
  # Validates multipart images, stages their Blob objects outside a DB
  # transaction, and coordinates one or more StagedPairUpdateService instances
  # as one atomic model update.
  class MultipartUpdateService
    class Error < StandardError; end

    Entry = Data.define(:purpose_name, :purpose, :payload)

    def initialize(
      record:,
      purpose: nil,
      payload: nil,
      updates: nil,
      attributes: {},
      blob_upload_service: StagedBlobUploadService,
      pair_update_service: StagedPairUpdateService
    )
      @record = record
      @entries = build_entries(purpose:, payload:, updates:)
      @attributes = attributes.to_h
      @blob_upload_service = blob_upload_service
      @pair_update_service = pair_update_service
      @crop_data = {}
      @staged_blobs = {}
      @called = false
    end

    def call(&block)
      raise Error, "service instances cannot be reused" if @called

      @called = true
      validate_payload_images!
      stage_required_blobs!
      updaters = build_pair_updaters
      updaters.each(&:validate_staged!)

      transaction_completed = false
      @record.class.transaction do
        updaters.each_with_index do |updater, index|
          updater.apply_in_transaction! do |record|
            yield record if block_given? && index == updaters.length - 1
          end
        end
        transaction_completed = true
      end
      unless transaction_completed
        raise StagedPairUpdateService::TransactionRolledBackError, "image pair transaction was rolled back"
      end

      @staged_blobs.clear
      @record
    ensure
      cleanup_staged_blobs
    end

    private

    def build_entries(purpose:, payload:, updates:)
      if updates
        if purpose || payload
          raise ArgumentError, "provide either purpose/payload or updates"
        end
        values = updates.to_h
      else
        raise ArgumentError, "purpose and payload are required" unless purpose && payload

        values = { purpose => payload }
      end
      raise ArgumentError, "at least one image update is required" if values.empty?

      values.map do |purpose_name, raw_payload|
        parsed = raw_payload.is_a?(MultipartPayload) ? raw_payload.validate! : MultipartPayload.parse(raw_payload)
        Entry.new(
          purpose_name: purpose_name.to_sym,
          purpose: @record.image_attachment_purpose_for(purpose_name),
          payload: parsed
        )
      end
    rescue NoMethodError
      raise ArgumentError, "updates must be a purpose-to-payload mapping"
    end

    def validate_payload_images!
      @entries.each do |entry|
        @crop_data[entry.purpose_name] = validate_payload_images(entry)
      end
    end

    def validate_payload_images(entry)
      validator = PairValidator.new(purpose: entry.purpose)
      case entry.payload.operation
      when :replace
        validator.call(
          source: entry.payload.source_upload,
          display: entry.payload.display_upload,
          crop_data: entry.payload.crop_data
        ).crop_data
      when :reedit
        crop_data = validator.crop_data!(entry.payload.crop_data)
        validator.image!(entry.payload.display_upload, role: :display, crop_data:)
        crop_data
      when :delete
        nil
      end
    end

    def stage_required_blobs!
      @entries.each do |entry|
        if entry.payload.operation == :replace
          @staged_blobs[[ entry.purpose_name, :source ]] = stage_blob(entry, :source, entry.payload.source_upload)
        end
        unless entry.payload.operation == :delete
          @staged_blobs[[ entry.purpose_name, :display ]] = stage_blob(entry, :display, entry.payload.display_upload)
        end
      end
    end

    def stage_blob(entry, role, upload)
      @blob_upload_service.new(
        record: @record,
        purpose: entry.purpose_name,
        role:,
        upload:
      ).call
    end

    def build_pair_updaters
      @entries.map.with_index do |entry, index|
        @pair_update_service.new(
          record: @record,
          purpose: entry.purpose_name,
          operation: entry.payload.operation,
          expected_snapshot: entry.payload.expected_snapshot,
          attributes: index.zero? ? @attributes : {},
          crop_data: @crop_data[entry.purpose_name],
          new_source_blob: @staged_blobs[[ entry.purpose_name, :source ]],
          new_display_blob: @staged_blobs[[ entry.purpose_name, :display ]]
        )
      end
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
