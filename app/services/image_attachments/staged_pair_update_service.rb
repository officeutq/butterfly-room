# frozen_string_literal: true

module ImageAttachments
  # Commits already-validated and uploaded source/display blobs as one image
  # pair. Uploading and image decoding stay outside the short DB transaction.
  class StagedPairUpdateService
    OPERATIONS = %i[replace reedit delete].freeze

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

    def self.capture(record:, purpose:)
      configuration = record.image_attachment_purpose_for(purpose)
      source = record.public_send(configuration.source_attachment).attachment
      display = record.public_send(configuration.display_attachment).attachment
      Snapshot.new(
        source_attachment_id: source&.id,
        source_blob_id: source&.blob_id,
        display_attachment_id: display&.id,
        display_blob_id: display&.blob_id
      )
    end

    def initialize(
      record:,
      purpose:,
      operation:,
      expected_snapshot:,
      attributes: {},
      crop_data: nil,
      new_source_blob: nil,
      new_display_blob: nil
    )
      @record = record
      @purpose = record.image_attachment_purpose_for(purpose)
      @operation = operation.to_sym if operation.respond_to?(:to_sym)
      @expected_snapshot = expected_snapshot
      @attributes = attributes.to_h.symbolize_keys
      @crop_data = crop_data
      @new_source_blob = new_source_blob
      @new_display_blob = new_display_blob
      @staged_blobs = { source: @new_source_blob, display: @new_display_blob }.compact
      @called = false

      validate_contract!
    end

    def call
      raise Error, "service instances cannot be reused" if @called

      committed = false
      transaction_completed = false

      validate_staged!
      @record.class.transaction do
        apply_in_transaction! { |record| yield record if block_given? }
        transaction_completed = true
      end

      # ActiveRecord::Rollback is swallowed by transaction. Treat it as a
      # failed image update so the staged blobs are not leaked.
      unless transaction_completed
        raise TransactionRolledBackError, "image pair transaction was rolled back"
      end

      committed = true
      @staged_blobs.clear
      @record
    ensure
      cleanup_staged_blobs unless committed
    end

    # Multi-purpose updates validate every image before opening their shared
    # transaction, then call this method for each purpose inside that one
    # transaction. The orchestrator retains staged Blob ownership until the
    # outer transaction commits and is responsible for failure cleanup.
    def validate_staged!
      raise Error, "service instances cannot be reused" if @called

      validate_operation_payload!
      validate_staged_blobs!
      @validated = true
      self
    end

    def apply_in_transaction!
      raise Error, "staged image pair must be validated first" unless @validated
      raise Error, "service instances cannot be reused" if @called
      unless @record.class.connection.transaction_open?
        raise Error, "image pair must be applied inside a transaction"
      end

      @called = true
      @record.lock! if @record.persisted?
      verify_expected_snapshot!
      lock_staged_blobs!

      @record.assign_attributes(@attributes)
      apply_operation!
      @record.save!
      yield @record if block_given?
      @staged_blobs.each_value { |blob| StagedBlobMetadata.clear!(blob) }
      @record
    end

    private

    def validate_contract!
      unless OPERATIONS.include?(@operation)
        raise ArgumentError, "operation must be replace, reedit, or delete"
      end
      unless @expected_snapshot.is_a?(Snapshot)
        raise ArgumentError, "expected_snapshot must be captured before staging the update"
      end

      [ @purpose.source_attachment, @purpose.display_attachment ].each do |name|
        @record.class.attachment_reflections.fetch(name.to_s)
      end
      unless @record.has_attribute?(@purpose.crop_attribute)
        raise ArgumentError, "unknown crop attribute: #{@purpose.crop_attribute}"
      end

      forbidden = [ @purpose.source_attachment, @purpose.display_attachment, @purpose.crop_attribute ]
      if (@attributes.keys & forbidden).any?
        raise ArgumentError, "attributes must not include image pair fields"
      end
    rescue KeyError => error
      raise ArgumentError, "unknown attachment: #{error.key}"
    end

    def validate_operation_payload!
      case @operation
      when :replace
        unless @new_source_blob && @new_display_blob && @crop_data
          raise InvalidStagedBlobError, "replace requires source, display, and crop data"
        end
      when :reedit
        unless @new_source_blob.nil? && @new_display_blob && @crop_data
          raise InvalidStagedBlobError, "reedit requires only display and crop data"
        end
      when :delete
        unless @new_source_blob.nil? && @new_display_blob.nil? && @crop_data.blank?
          raise InvalidStagedBlobError, "delete does not accept staged blobs or crop data"
        end
      end

      return unless @new_source_blob && @new_source_blob.id == @new_display_blob&.id

      raise InvalidStagedBlobError, "source and display blobs must be independent"
    end

    def validate_staged_blobs!
      @staged_blobs.each do |role, blob|
        validate_staged_blob!(blob, role:, check_storage: true)
      end
    end

    def validate_staged_blob!(blob, role:, check_storage:)
      unless blob.is_a?(ActiveStorage::Blob) && blob.persisted?
        raise InvalidStagedBlobError, "staged blob is invalid"
      end

      blob.reload
      byte_limit = PairValidator::BYTE_LIMITS.fetch(role)
      valid = !blob.attachments.exists? &&
        blob.content_type == PairValidator::JPEG_CONTENT_TYPE &&
        blob.byte_size.between?(1, byte_limit) &&
        blob.service_name == attachment_service_name(role) &&
        StagedBlobMetadata.active?(blob, purpose: @purpose, role:)
      valid &&= blob.service.exist?(blob.key) if check_storage
      raise InvalidStagedBlobError, "staged blob is missing, expired, attached, or not owned" unless valid
    rescue ActiveRecord::RecordNotFound
      raise InvalidStagedBlobError, "staged blob no longer exists"
    end

    def lock_staged_blobs!
      return if @staged_blobs.empty?

      ids = @staged_blobs.values.map(&:id).sort
      locked = ActiveStorage::Blob.lock.where(id: ids).order(:id).index_by(&:id)
      unless locked.length == ids.length
        raise InvalidStagedBlobError, "staged blob no longer exists"
      end

      @staged_blobs.transform_values! { |blob| locked.fetch(blob.id) }
      @staged_blobs.each { |role, blob| validate_staged_blob!(blob, role:, check_storage: false) }
      @new_source_blob = @staged_blobs[:source]
      @new_display_blob = @staged_blobs[:display]
    end

    def verify_expected_snapshot!
      source = locked_attachment(@purpose.source_attachment)
      display = locked_attachment(@purpose.display_attachment)
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
      @record.association("#{name}_attachment").reload if @record.persisted?
      attachment = @record.public_send(name).attachment
      attachment&.lock! if @record.persisted?
      attachment
    end

    def apply_operation!
      case @operation
      when :replace
        assign_replacement!
      when :reedit
        assign_reedit!
      when :delete
        assign_delete!
      end
    end

    def assign_replacement!
      @record.public_send("#{@purpose.source_attachment}=", @new_source_blob)
      @record.public_send("#{@purpose.display_attachment}=", @new_display_blob)
      @record.public_send("#{@purpose.crop_attribute}=", persisted_crop_data(@new_source_blob))
    end

    def assign_reedit!
      source_blob = current_blob(@purpose.source_attachment)
      raise InvalidStagedBlobError, "an editing source is required" unless source_blob
      if source_blob.id == @new_display_blob.id
        raise InvalidStagedBlobError, "source and display blobs must be independent"
      end

      validated_crop = validated_crop_data
      validate_existing_source_crop!(source_blob, validated_crop)
      @record.public_send("#{@purpose.display_attachment}=", @new_display_blob)
      @record.public_send(
        "#{@purpose.crop_attribute}=",
        validated_crop.merge("sourceBlobId" => source_blob.id)
      )
    end

    def assign_delete!
      @record.public_send("#{@purpose.source_attachment}=", nil)
      @record.public_send("#{@purpose.display_attachment}=", nil)
      @record.public_send("#{@purpose.crop_attribute}=", {})
    end

    def current_blob(name)
      attachment = @record.public_send(name)
      attachment.blob if attachment.attached?
    end

    def persisted_crop_data(source_blob)
      validated_crop_data.merge("sourceBlobId" => source_blob.id)
    end

    def validated_crop_data
      PairValidator.new(purpose: @purpose).crop_data!(@crop_data)
    rescue PairValidator::Invalid => error
      raise InvalidCropDataError, error.message
    end

    def validate_existing_source_crop!(source_blob, new_crop)
      stored_data = @record.public_send(@purpose.crop_attribute).to_h
      stored_crop = PairValidator.new(purpose: @purpose).crop_data!(stored_data)
      return if stored_data["sourceBlobId"] == source_blob.id && stored_crop["source"] == new_crop["source"]

      raise InvalidCropDataError, "crop data does not match the current editing source"
    rescue PairValidator::Invalid
      raise InvalidCropDataError, "stored crop data does not match the current editing source"
    end

    def attachment_service_name(role)
      name = attachment_reflection(role).options[:service_name]
      name = name.call(@record) if name.respond_to?(:call)
      (name || ActiveStorage::Blob.service.name).to_s
    end

    def attachment_reflection(role)
      attachment_name = role == :source ? @purpose.source_attachment : @purpose.display_attachment
      @record.class.attachment_reflections.fetch(attachment_name.to_s)
    end

    def cleanup_staged_blobs
      blobs = @staged_blobs.values.compact.select do |blob|
        blob.is_a?(ActiveStorage::Blob) && blob.persisted?
      end
      blobs.uniq(&:id).each do |blob|
        StagedBlobPurgeService.new(blob:).call
      rescue StandardError => error
        Rails.logger.error(
          "[ImageAttachments::StagedPairUpdateService] staged blob cleanup failed " \
          "blob=#{blob.id} error=#{error.class.name}"
        )
      end
    end
  end
end
