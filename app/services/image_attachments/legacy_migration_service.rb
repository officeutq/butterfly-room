# frozen_string_literal: true

module ImageAttachments
  class LegacyMigrationService
    APPLY_CONFIRMATION = "APPLY_LEGACY_IMAGE_PAIR_MIGRATION"
    TARGETS = {
      "User" => { attachment: :avatar, purposes: %i[cover avatar] },
      "Store" => { attachment: :thumbnail, purposes: %i[thumbnail] },
      "Booth" => { attachment: :thumbnail_image, purposes: %i[thumbnail] }
    }.freeze

    BlobUpload = Data.define(:tempfile, :content_type)
    Entry = Data.define(
      :status,
      :record_type,
      :record_id,
      :purpose,
      :legacy_attachment_id,
      :legacy_blob_id,
      :source_attachment_id,
      :source_blob_id,
      :display_attachment_id,
      :display_blob_id,
      :input_width,
      :input_height,
      :source_width,
      :source_height,
      :output_width,
      :output_height,
      :enlarged,
      :reduced,
      :error_class
    )
    Result = Data.define(
      :dry_run,
      :record_type,
      :record_id,
      :min_attachment_id,
      :max_attachment_id,
      :after_attachment_id,
      :limit,
      :target_count,
      :selected_count,
      :last_attachment_id,
      :status_counts,
      :entries
    )

    class Error < StandardError; end
    class StaleLegacyError < Error; end

    def initialize(
      apply: false,
      confirmation: nil,
      record_type: nil,
      record_id: nil,
      min_attachment_id: nil,
      max_attachment_id: nil,
      after_attachment_id: nil,
      limit: nil,
      expected_attachment_id: nil,
      expected_blob_id: nil,
      builder_class: LegacyPairBuilder,
      pair_update_service: StagedPairUpdateService
    )
      @apply = ActiveModel::Type::Boolean.new.cast(apply)
      @confirmation = confirmation.to_s
      @record_type = normalize_record_type(record_type)
      @record_id = optional_positive_integer(record_id, :record_id)
      @min_attachment_id = optional_positive_integer(min_attachment_id, :min_attachment_id)
      @max_attachment_id = optional_positive_integer(max_attachment_id, :max_attachment_id)
      @after_attachment_id = optional_positive_integer(after_attachment_id, :after_attachment_id)
      @limit = optional_positive_integer(limit, :limit)
      @expected_attachment_id = optional_positive_integer(expected_attachment_id, :expected_attachment_id)
      @expected_blob_id = optional_positive_integer(expected_blob_id, :expected_blob_id)
      @builder_class = builder_class
      @pair_update_service = pair_update_service

      validate_options!
    end

    def call
      scope = target_scope
      target_count = scope.count
      selected = scope.order("active_storage_attachments.id")
      selected = selected.limit(@limit) if @limit
      selected = selected.to_a

      entries = selected.flat_map do |attachment|
        Rails.logger.silence(Logger::UNKNOWN) { process_target(attachment) }
      end
      if selected.empty? && @expected_attachment_id
        entries = missing_expected_target_entries
      end

      Result.new(
        dry_run: !@apply,
        record_type: @record_type,
        record_id: @record_id,
        min_attachment_id: @min_attachment_id,
        max_attachment_id: @max_attachment_id,
        after_attachment_id: @after_attachment_id,
        limit: @limit,
        target_count:,
        selected_count: selected.size,
        last_attachment_id: selected.last&.id,
        status_counts: entries.map(&:status).tally,
        entries:
      )
    end

    private

    def target_scope
      base = ActiveStorage::Attachment.joins(:blob).includes(:blob)
      scopes = TARGETS.map do |record_type, target|
        base.where(record_type:, name: target.fetch(:attachment).to_s)
      end
      scope = scopes.reduce { |combined, candidate| combined.or(candidate) }
      scope = scope.where(record_type: @record_type) if @record_type
      scope = scope.where(record_id: @record_id) if @record_id
      scope = scope.where("active_storage_attachments.id >= ?", @min_attachment_id) if @min_attachment_id
      scope = scope.where("active_storage_attachments.id <= ?", @max_attachment_id) if @max_attachment_id
      scope = scope.where("active_storage_attachments.id > ?", @after_attachment_id) if @after_attachment_id
      scope
    end

    def process_target(legacy_attachment)
      target = TARGETS.fetch(legacy_attachment.record_type)
      record = legacy_attachment.record_type.constantize.find(legacy_attachment.record_id)
      unless expected_target?(legacy_attachment) && current_legacy_target?(record, legacy_attachment, target)
        return failure_entries(record, legacy_attachment, target.fetch(:purposes), "failed_conflict", StaleLegacyError.new)
      end

      if record.is_a?(User)
        process_user(record, legacy_attachment)
      else
        [ process_purpose(record, legacy_attachment, target.fetch(:purposes).first) ]
      end
    rescue ActiveRecord::RecordNotFound => error
      purposes = TARGETS.fetch(legacy_attachment.record_type).fetch(:purposes)
      failure_entries(nil, legacy_attachment, purposes, "failed_record_missing", error)
    rescue StandardError => error
      Rails.logger.error(
        "[ImageAttachments::LegacyMigrationService] unexpected target failure " \
        "record=#{legacy_attachment.record_type}:#{legacy_attachment.record_id} error=#{error.class.name}"
      )
      purposes = TARGETS.fetch(legacy_attachment.record_type).fetch(:purposes)
      failure_entries(nil, legacy_attachment, purposes, "failed_unexpected", error)
    end

    def process_user(record, legacy_attachment)
      avatar_state = pair_state(record, :avatar, legacy_attachment)
      cover_state = pair_state(record, :cover, legacy_attachment)

      if avatar_state == :complete
        cover_entry = case cover_state
        when :complete
          entry_for(record, legacy_attachment, :cover, status: "skipped_migrated")
        when :empty
          entry_for(record, legacy_attachment, :cover, status: "skipped_no_legacy_source")
        else
          entry_for(record, legacy_attachment, :cover, status: "failed_partial_state")
        end
        return [ cover_entry, entry_for(record, legacy_attachment, :avatar, status: "skipped_migrated") ]
      end

      if avatar_state == :partial
        cover_entry = case cover_state
        when :complete
          entry_for(record, legacy_attachment, :cover, status: "skipped_migrated")
        when :partial
          entry_for(record, legacy_attachment, :cover, status: "failed_partial_state")
        else
          entry_for(record, legacy_attachment, :cover, status: "failed_blocked_by_avatar")
        end
        return [
          cover_entry,
          entry_for(record, legacy_attachment, :avatar, status: "failed_partial_state")
        ]
      end

      if cover_state == :partial
        return [
          entry_for(record, legacy_attachment, :cover, status: "failed_partial_state"),
          entry_for(record, legacy_attachment, :avatar, status: "failed_blocked_by_cover")
        ]
      end

      cover_entry = if cover_state == :complete
        entry_for(record, legacy_attachment, :cover, status: "skipped_migrated")
      else
        process_purpose(record, legacy_attachment, :cover)
      end
      return [ cover_entry, entry_for(record, legacy_attachment, :avatar, status: "failed_blocked_by_cover") ] if failed?(cover_entry)

      [ cover_entry, process_purpose(record, legacy_attachment, :avatar) ]
    end

    def process_purpose(record, legacy_attachment, purpose_name)
      state = pair_state(record, purpose_name, legacy_attachment)
      return entry_for(record, legacy_attachment, purpose_name, status: "skipped_migrated") if state == :complete
      return entry_for(record, legacy_attachment, purpose_name, status: "failed_partial_state") if state == :partial

      verify_legacy_target!(record, legacy_attachment)
      purpose = record.image_attachment_purpose_for(purpose_name)
      expected_snapshot = @pair_update_service.capture(record:, purpose: purpose_name)
      build_result = @builder_class.new(
        record:,
        purpose: purpose_name,
        legacy_blob: legacy_attachment.blob
      ).call(dry_run: !@apply)
      return entry_for(record, legacy_attachment, purpose_name, status: "eligible", build_result:) unless @apply

      commit_pair(record, legacy_attachment, purpose_name, purpose, expected_snapshot, build_result)
      entry_for(record.reload, legacy_attachment, purpose_name, status: "migrated", build_result:)
    rescue LegacyPairBuilder::InvalidImageError => error
      entry_for(record, legacy_attachment, purpose_name, status: "failed_invalid_image", error:)
    rescue LegacyPairBuilder::UploadFailedError, StagedBlobUploadService::UploadFailedError => error
      entry_for(record, legacy_attachment, purpose_name, status: "failed_upload", error:)
    rescue StaleLegacyError, StagedPairUpdateService::StalePairError => error
      entry_for(record, legacy_attachment, purpose_name, status: "failed_conflict", error:)
    rescue StagedPairUpdateService::Error, ActiveRecord::ActiveRecordError => error
      entry_for(record, legacy_attachment, purpose_name, status: "failed_save", error:)
    rescue StandardError => error
      Rails.logger.error(
        "[ImageAttachments::LegacyMigrationService] unexpected purpose failure " \
        "record=#{record.class.name}:#{record.id} purpose=#{purpose_name} error=#{error.class.name}"
      )
      entry_for(record, legacy_attachment, purpose_name, status: "failed_unexpected", error:)
    end

    def commit_pair(record, legacy_attachment, purpose_name, purpose, expected_snapshot, build_result)
      committed = false
      updater = @pair_update_service.new(
        record:,
        purpose: purpose_name,
        operation: :replace,
        expected_snapshot:,
        crop_data: build_result.crop_data,
        new_source_blob: build_result.source_blob,
        new_display_blob: build_result.display_blob
      )
      updater.call do
        verify_legacy_target!(record, legacy_attachment) unless purpose.display_attachment == legacy_attachment.name.to_sym
      end
      committed = true
    ensure
      purge_generated_blobs(build_result) if build_result && !committed
    end

    def pair_state(record, purpose_name, legacy_attachment)
      purpose = record.image_attachment_purpose_for(purpose_name)
      source = record.public_send(purpose.source_attachment).attachment
      display = record.public_send(purpose.display_attachment).attachment
      crop_data = record.public_send(purpose.crop_attribute).to_h

      if source && display && crop_data.present?
        return current_pair_valid?(record, purpose_name, source, display, crop_data) ? :complete : :partial
      end

      display_is_legacy = purpose.display_attachment == legacy_attachment.name.to_sym &&
        attachment_matches?(display, legacy_attachment.id, legacy_attachment.blob_id)
      display_is_empty = purpose.display_attachment != legacy_attachment.name.to_sym && display.nil?
      return :empty if source.nil? && crop_data.blank? && (display_is_legacy || display_is_empty)

      :partial
    end

    def current_pair_valid?(record, purpose_name, source, display, crop_data)
      return false if source.blob_id == display.blob_id || crop_data["sourceBlobId"] != source.blob_id
      return false unless source.blob.service.exist?(source.blob.key) && display.blob.service.exist?(display.blob.key)

      purpose = record.image_attachment_purpose_for(purpose_name)
      source.blob.open do |source_file|
        display.blob.open do |display_file|
          PairValidator.new(purpose:).call(
            source: BlobUpload.new(tempfile: source_file, content_type: source.blob.content_type),
            display: BlobUpload.new(tempfile: display_file, content_type: display.blob.content_type),
            crop_data:
          )
        end
      end
      true
    rescue ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError,
           PairValidator::Invalid, MiniMagick::Error, MiniMagick::Invalid
      false
    end

    def verify_legacy_target!(record, legacy_attachment)
      target = TARGETS.fetch(record.class.name)
      record.association("#{target.fetch(:attachment)}_attachment").reload
      current = record.public_send(target.fetch(:attachment)).attachment
      return if attachment_matches?(current, legacy_attachment.id, legacy_attachment.blob_id)

      raise StaleLegacyError, "legacy attachment changed during migration"
    end

    def current_legacy_target?(record, legacy_attachment, target)
      current = record.public_send(target.fetch(:attachment)).attachment
      attachment_matches?(current, legacy_attachment.id, legacy_attachment.blob_id)
    end

    def attachment_matches?(attachment, attachment_id, blob_id)
      attachment&.id == attachment_id && attachment&.blob_id == blob_id
    end

    def expected_target?(legacy_attachment)
      return true unless @expected_attachment_id

      legacy_attachment.id == @expected_attachment_id && legacy_attachment.blob_id == @expected_blob_id
    end

    def entry_for(record, legacy_attachment, purpose_name, status:, build_result: nil, error: nil)
      purpose = record&.image_attachment_purpose_for(purpose_name)
      source = record&.public_send(purpose&.source_attachment)&.attachment
      display = record&.public_send(purpose&.display_attachment)&.attachment
      crop_data = record&.public_send(purpose&.crop_attribute).to_h

      Entry.new(
        status:,
        record_type: legacy_attachment.record_type,
        record_id: legacy_attachment.record_id,
        purpose: purpose_name.to_s,
        legacy_attachment_id: legacy_attachment.id,
        legacy_blob_id: legacy_attachment.blob_id,
        source_attachment_id: source&.id,
        source_blob_id: source&.blob_id,
        display_attachment_id: display&.id,
        display_blob_id: display&.blob_id,
        input_width: build_result&.input_width,
        input_height: build_result&.input_height,
        source_width: build_result&.source_width || crop_data.dig("source", "width"),
        source_height: build_result&.source_height || crop_data.dig("source", "height"),
        output_width: purpose&.output_width,
        output_height: purpose&.output_height,
        enlarged: build_result&.enlarged,
        reduced: build_result&.reduced,
        error_class: error&.class&.name
      )
    end

    def failure_entries(record, legacy_attachment, purposes, status, error)
      purposes.map do |purpose|
        entry_for(record, legacy_attachment, purpose, status:, error:)
      end
    end

    def missing_expected_target_entries
      target = TARGETS.fetch(@record_type)
      placeholder = Struct.new(:record_type, :record_id, :id, :blob_id).new(
        @record_type,
        @record_id,
        @expected_attachment_id,
        @expected_blob_id
      )
      record = @record_type.constantize.find_by(id: @record_id)
      failure_entries(record, placeholder, target.fetch(:purposes), "failed_conflict", StaleLegacyError.new)
    end

    def purge_generated_blobs(build_result)
      [ build_result.source_blob, build_result.display_blob ].compact.each do |blob|
        next unless blob.persisted? && StagedBlobMetadata.owned?(blob)

        StagedBlobPurgeService.new(blob:).call
      rescue ActiveRecord::RecordNotFound
        nil
      end
    end

    def failed?(entry)
      entry.status.start_with?("failed_")
    end

    def normalize_record_type(value)
      normalized = value.to_s.strip
      return nil if normalized.empty?
      return normalized if TARGETS.key?(normalized)

      raise ArgumentError, "record_type must be User, Store, or Booth"
    end

    def optional_positive_integer(value, name)
      return nil if value.nil? || value.to_s.strip.empty?

      integer = Integer(value)
      raise ArgumentError, "#{name} must be positive" unless integer.positive?

      integer
    rescue TypeError, ArgumentError
      raise ArgumentError, "#{name} must be a positive integer"
    end

    def validate_options!
      raise ArgumentError, "record_type is required when record_id is specified" if @record_id && !@record_type
      if @min_attachment_id && @max_attachment_id && @min_attachment_id > @max_attachment_id
        raise ArgumentError, "min_attachment_id must not exceed max_attachment_id"
      end
      unless @expected_attachment_id.nil? == @expected_blob_id.nil?
        raise ArgumentError, "expected_attachment_id and expected_blob_id must be provided together"
      end
      if @expected_attachment_id && !@record_id
        raise ArgumentError, "record_type and record_id are required with expected IDs"
      end

      return unless @apply

      raise ArgumentError, "limit is required when apply is enabled" unless @limit
      unless @record_id || @max_attachment_id
        raise ArgumentError, "record_id or max_attachment_id is required when apply is enabled"
      end
      if @record_id && !@expected_attachment_id
        raise ArgumentError, "expected IDs are required for a record-scoped apply"
      end
      unless @confirmation == APPLY_CONFIRMATION
        raise ArgumentError, "confirmation must be #{APPLY_CONFIRMATION} when apply is enabled"
      end
    end
  end
end
