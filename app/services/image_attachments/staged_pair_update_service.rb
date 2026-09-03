# frozen_string_literal: true

module ImageAttachments
  # Prototype for committing two already-uploaded blobs and their crop data as
  # one logical image update. Content validation belongs before this service.
  class StagedPairUpdateService
    Snapshot = Data.define(
      :source_attachment_id,
      :source_blob_id,
      :display_attachment_id,
      :display_blob_id
    )

    class Error < StandardError; end
    class StalePairError < Error; end
    class InvalidStagedBlobError < Error; end
    class InvalidCropDataError < Error; end
    class TransactionRolledBackError < Error; end

    def self.capture(record:, source_attachment_name:, display_attachment_name:)
      source = record.public_send(source_attachment_name).attachment
      display = record.public_send(display_attachment_name).attachment
      Snapshot.new(
        source_attachment_id: source&.id,
        source_blob_id: source&.blob_id,
        display_attachment_id: display&.id,
        display_blob_id: display&.blob_id
      )
    end

    def initialize(
      record:,
      source_attachment_name:,
      display_attachment_name:,
      crop_attribute:,
      crop_data:,
      expected_snapshot:,
      new_display_blob:,
      new_source_blob: nil
    )
      @record = record
      @source_attachment_name = source_attachment_name.to_sym
      @display_attachment_name = display_attachment_name.to_sym
      @crop_attribute = crop_attribute.to_sym
      @crop_data = crop_data
      @expected_snapshot = expected_snapshot
      @new_source_blob = new_source_blob
      @new_display_blob = new_display_blob
      @pending_blobs = [ @new_source_blob, @new_display_blob ].compact.uniq
      @called = false

      validate_contract!
    end

    def call
      raise Error, "service instances cannot be reused" if @called

      @called = true
      committed = false
      transaction_completed = false
      old_blobs = []

      validate_staged_blobs!
      @record.class.transaction do
        @record.lock! if @record.persisted?
        verify_expected_snapshot!

        current_source_blob = current_blob(@source_attachment_name)
        source_blob = @new_source_blob || current_source_blob
        raise InvalidStagedBlobError, "an editing source is required" unless source_blob
        raise InvalidStagedBlobError, "source and display blobs must be independent" if source_blob.id == @new_display_blob.id

        old_blobs << current_source_blob if @new_source_blob
        old_blobs << current_blob(@display_attachment_name)
        @record.public_send("#{@source_attachment_name}=", @new_source_blob) if @new_source_blob
        @record.public_send("#{@display_attachment_name}=", @new_display_blob)
        @record.public_send("#{@crop_attribute}=", persisted_crop_data(source_blob))
        @record.save!
        yield @record if block_given?
        transaction_completed = true
      end
      # ActiveRecord::Rollback is intentionally swallowed by transaction. Do
      # not mistake that path for a commit and leak the staged blobs.
      raise TransactionRolledBackError, "image pair transaction was rolled back" unless transaction_completed

      committed = true
      @pending_blobs.clear
      old_blobs.compact.uniq.each { |blob| purge_replaced_blob_later(blob) }
      @record
    ensure
      cleanup_pending_blobs unless committed
    end

    private

    def validate_contract!
      unless @expected_snapshot.is_a?(Snapshot)
        raise ArgumentError, "expected_snapshot must be captured before staging the update"
      end
      [ @source_attachment_name, @display_attachment_name ].each do |name|
        @record.class.attachment_reflections.fetch(name.to_s)
      end
      unless @record.has_attribute?(@crop_attribute)
        raise ArgumentError, "unknown crop attribute: #{@crop_attribute}"
      end
      raise ArgumentError, "new_display_blob is required" unless @new_display_blob
    rescue KeyError => error
      raise ArgumentError, "unknown attachment: #{error.key}"
    end

    def validate_staged_blobs!
      @pending_blobs.each do |blob|
        unless blob.is_a?(ActiveStorage::Blob) && blob.persisted? && !blob.attachments.exists? && blob.service.exist?(blob.key)
          raise InvalidStagedBlobError, "staged blob is missing, already attached, or not stored"
        end
      end
    end

    def verify_expected_snapshot!
      source = locked_attachment(@source_attachment_name)
      display = locked_attachment(@display_attachment_name)
      actual = Snapshot.new(
        source_attachment_id: source&.id,
        source_blob_id: source&.blob_id,
        display_attachment_id: display&.id,
        display_blob_id: display&.blob_id
      )
      raise StalePairError, "image pair changed after editing started" unless actual == @expected_snapshot
    rescue ActiveRecord::RecordNotFound
      raise StalePairError, "image pair changed after editing started"
    end

    def locked_attachment(name)
      @record.association("#{name}_attachment").reload
      attachment = @record.public_send(name).attachment
      attachment&.lock!
      attachment
    end

    def current_blob(name)
      attachment = @record.public_send(name)
      attachment.blob if attachment.attached?
    end

    def persisted_crop_data(source_blob)
      unless @crop_data.is_a?(Hash) && @crop_data["schemaVersion"] == 1 &&
          @crop_data["source"].is_a?(Hash) && @crop_data["crop"].is_a?(Hash) && @crop_data["output"].is_a?(Hash)
        raise InvalidCropDataError, "crop data has an unsupported schema"
      end

      @crop_data.deep_dup.merge("sourceBlobId" => source_blob.id)
    end

    def purge_replaced_blob_later(blob)
      blob.reload
      blob.purge_later unless blob.attachments.exists?
    rescue ActiveRecord::RecordNotFound
      nil
    rescue StandardError => error
      Rails.logger.error("[ImageAttachments::StagedPairUpdateService] old blob purge enqueue failed blob=#{blob.id} error=#{error.class.name}")
    end

    def cleanup_pending_blobs
      @pending_blobs.each do |blob|
        blob.reload
        blob.purge unless blob.attachments.exists?
      rescue ActiveRecord::RecordNotFound
        nil
      rescue StandardError => error
        Rails.logger.error("[ImageAttachments::StagedPairUpdateService] staged blob cleanup failed blob=#{blob.id} error=#{error.class.name}")
      end
    end
  end
end
