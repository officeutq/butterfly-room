# frozen_string_literal: true

require "mini_magick"

module ImageAttachments
  class InventoryService
    TARGET_ATTACHMENTS = {
      "Store" => { "thumbnail" => [ 1920, 1080 ] },
      "Booth" => { "thumbnail_image" => [ 1920, 1080 ] },
      "User" => { "avatar" => [ 1024, 1024 ] }
    }.freeze
    CANDIDATE_CONTENT_TYPES = %w[
      image/heic
      image/heif
      application/octet-stream
    ].freeze
    CANDIDATE_EXTENSIONS = %w[.heic .heif].freeze

    Upload = Data.define(:tempfile, :original_filename)
    Entry = Data.define(
      :attachment_id,
      :record_type,
      :record_id,
      :attachment_name,
      :blob_id,
      :filename,
      :content_type,
      :byte_size,
      :metadata_candidate,
      :stored,
      :actual_format,
      :convertible,
      :status,
      :error_class
    )
    Result = Data.define(
      :selection,
      :limit,
      :after_attachment_id,
      :last_attachment_id,
      :target_count,
      :metadata_candidate_count,
      :inspected_count,
      :status_counts,
      :entries
    )

    def initialize(
      inspect_all: false,
      limit: nil,
      after_attachment_id: nil,
      record_type: nil,
      record_id: nil
    )
      @inspect_all = ActiveModel::Type::Boolean.new.cast(inspect_all)
      @limit = optional_positive_integer(limit, :limit)
      @after_attachment_id = optional_positive_integer(after_attachment_id, :after_attachment_id)
      @record_type = normalize_record_type(record_type)
      @record_id = optional_positive_integer(record_id, :record_id)

      validate_options!
    end

    def call
      target_scope = filtered_target_scope
      candidate_scope = metadata_candidate_scope(target_scope)
      selected_scope = @inspect_all ? target_scope : candidate_scope
      selected_scope = selected_scope.limit(@limit) if @limit

      entries = selected_scope.order("active_storage_attachments.id").map do |attachment|
        inspect_attachment(attachment)
      end

      Result.new(
        selection: @inspect_all ? "all_target_attachments" : "metadata_candidates",
        limit: @limit,
        after_attachment_id: @after_attachment_id,
        last_attachment_id: entries.last&.attachment_id,
        target_count: target_scope.count,
        metadata_candidate_count: candidate_scope.count,
        inspected_count: entries.size,
        status_counts: entries.map(&:status).tally,
        entries:
      )
    end

    private

    def filtered_target_scope
      base_scope = ActiveStorage::Attachment.joins(:blob).includes(:blob)
      pair_scopes = TARGET_ATTACHMENTS.flat_map do |record_type, attachments|
        attachments.keys.map do |attachment_name|
          base_scope.where(record_type:, name: attachment_name)
        end
      end
      scope = pair_scopes.reduce { |combined, pair_scope| combined.or(pair_scope) }
      scope = scope.where(record_type: @record_type) if @record_type
      scope = scope.where(record_id: @record_id) if @record_id
      if @after_attachment_id
        scope = scope.where("active_storage_attachments.id > ?", @after_attachment_id)
      end
      scope
    end

    def metadata_candidate_scope(scope)
      scope.where(
        <<~SQL.squish,
          LOWER(COALESCE(active_storage_blobs.content_type, '')) IN (?)
          OR LOWER(active_storage_blobs.filename) LIKE ?
          OR LOWER(active_storage_blobs.filename) LIKE ?
        SQL
        CANDIDATE_CONTENT_TYPES,
        *CANDIDATE_EXTENSIONS.map { |extension| "%#{extension}" }
      )
    end

    def inspect_attachment(attachment)
      # JSON LinesへS3キーを含む内部ログを混在させず、失敗はentryへ記録する。
      Rails.logger.silence(Logger::UNKNOWN) do
        inspect_attachment_without_logging(attachment)
      end
    end

    def inspect_attachment_without_logging(attachment)
      blob = attachment.blob
      attributes = base_entry_attributes(attachment, blob)
      stored = blob.service.exist?(blob.key)
      return Entry.new(**attributes, stored: false, status: "missing", error_class: nil) unless stored

      blob.open do |file|
        actual_format = identify_format(file.path)
        convertible = convertible_to_jpeg?(attachment, blob, file)

        Entry.new(
          **attributes,
          stored: true,
          actual_format:,
          convertible:,
          status: inventory_status(blob, actual_format, convertible),
          error_class: nil
        )
      end
    rescue ActiveStorage::FileNotFoundError => error
      Entry.new(**attributes, stored: false, status: "missing", error_class: error.class.name)
    rescue MiniMagick::Error, MiniMagick::Invalid => error
      Entry.new(
        **attributes,
        stored: true,
        convertible: false,
        status: "unreadable",
        error_class: error.class.name
      )
    rescue NormalizeService::InvalidImageError => error
      Entry.new(
        **attributes,
        stored: true,
        actual_format: local_variable_defined?(:actual_format) ? actual_format : nil,
        convertible: false,
        status: "conversion_failed",
        error_class: error.class.name
      )
    rescue StandardError => error
      Entry.new(
        **attributes,
        stored: nil,
        convertible: false,
        status: "inspection_failed",
        error_class: error.class.name
      )
    end

    def base_entry_attributes(attachment, blob)
      {
        attachment_id: attachment.id,
        record_type: attachment.record_type,
        record_id: attachment.record_id,
        attachment_name: attachment.name,
        blob_id: blob.id,
        filename: blob.filename.to_s,
        content_type: blob.content_type,
        byte_size: blob.byte_size,
        metadata_candidate: metadata_candidate?(blob),
        actual_format: nil,
        convertible: nil
      }
    end

    def identify_format(path)
      output = MiniMagick.identify(timeout: NormalizeService::DEFAULT_PROCESSING_TIMEOUT_SECONDS) do |command|
        apply_resource_limits(command)
        command.format("%m")
        command << "#{path}[0]"
      end

      output.strip.upcase
    end

    def convertible_to_jpeg?(attachment, blob, file)
      max_width, max_height = TARGET_ATTACHMENTS.fetch(attachment.record_type).fetch(attachment.name)
      upload = Upload.new(tempfile: file, original_filename: blob.filename.to_s)
      converted = false

      NormalizeService.new(upload:, max_width:, max_height:).call do
        converted = true
      end

      converted
    end

    def inventory_status(blob, actual_format, convertible)
      return "conversion_failed" unless convertible
      return "ok" if actual_format == "JPEG" && canonical_jpeg_metadata?(blob)
      return "metadata_mismatch" if actual_format == "JPEG"

      "needs_normalization"
    end

    def canonical_jpeg_metadata?(blob)
      extension = File.extname(blob.filename.to_s).downcase
      blob.content_type.to_s.downcase == "image/jpeg" && %w[.jpg .jpeg].include?(extension)
    end

    def metadata_candidate?(blob)
      CANDIDATE_CONTENT_TYPES.include?(blob.content_type.to_s.downcase) ||
        CANDIDATE_EXTENSIONS.include?(File.extname(blob.filename.to_s).downcase)
    end

    def apply_resource_limits(command)
      command.limit("memory", NormalizeService::MEMORY_LIMIT)
      command.limit("map", NormalizeService::MAP_LIMIT)
      command.limit("disk", NormalizeService::DISK_LIMIT)
      command.limit("thread", NormalizeService::THREAD_LIMIT.to_s)
      command.limit("width", NormalizeService::MAX_SOURCE_DIMENSION.to_s)
      command.limit("height", NormalizeService::MAX_SOURCE_DIMENSION.to_s)
    end

    def normalize_record_type(value)
      record_type = value.to_s.strip
      return nil if record_type.empty?
      return record_type if TARGET_ATTACHMENTS.key?(record_type)

      raise ArgumentError, "record_type must be Store, Booth, or User"
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
      if @record_id && !@record_type
        raise ArgumentError, "record_type is required when record_id is specified"
      end
      if @inspect_all && @limit.nil? && @record_id.nil?
        raise ArgumentError, "limit is required when inspect_all is enabled"
      end
    end
  end
end
