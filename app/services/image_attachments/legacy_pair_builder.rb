# frozen_string_literal: true

require "mini_magick"
require "tempfile"

module ImageAttachments
  # Converts one legacy display Blob into a validated, independently stored
  # editing source and deterministic display image. Generated Blobs remain
  # staged until LegacyMigrationService commits them to the target record.
  class LegacyPairBuilder
    RATIOS = {
      "square" => [ 1, 1 ],
      "social" => [ 40, 21 ]
    }.freeze
    SUPPORTED_FORMATS = NormalizeService::SUPPORTED_FORMATS
    MAX_INPUT_BYTES = 20.megabytes
    MAX_INPUT_DIMENSION = 8192
    MAX_INPUT_PIXELS = 32_000_000
    MAX_INPUT_ASPECT_RATIO = 8
    MAX_SOURCE_DIMENSION = PairValidator::MAX_SOURCE_EDGE
    MAX_SOURCE_PIXELS = PairValidator::MAX_SOURCE_PIXELS
    SOURCE_QUALITY = 94
    DISPLAY_QUALITY = 90
    PROCESSING_TIMEOUT_SECONDS = 30

    Upload = Data.define(:tempfile, :content_type)

    Result = Data.define(
      :source_blob,
      :display_blob,
      :crop_data,
      :input_width,
      :input_height,
      :source_width,
      :source_height,
      :enlarged,
      :reduced
    )

    class Error < StandardError; end
    class InvalidImageError < Error; end
    class UploadFailedError < Error; end

    def initialize(record:, purpose:, legacy_blob:, blob_upload_service: StagedBlobUploadService)
      @record = record
      @purpose_name = purpose.to_sym
      @purpose = record.image_attachment_purpose_for(@purpose_name)
      @legacy_blob = legacy_blob
      @ratio_key = @purpose.ratio_key.to_s
      @output_width = Integer(@purpose.output_width)
      @output_height = Integer(@purpose.output_height)
      @blob_upload_service = blob_upload_service
      @pending_blobs = []
      @transferred = false
      @called = false

      RATIOS.fetch(@ratio_key) { raise ArgumentError, "unknown ratio_key: #{@ratio_key}" }
    end

    def call(dry_run: false)
      raise Error, "builder instances cannot be reused" if @called

      @called = true
      validate_legacy_blob!

      @legacy_blob.open do |input|
        input_image = identify(input.path)
        validate_input!(input_image)

        Tempfile.create([ "legacy-source", ".jpg" ], binmode: true) do |source_file|
          prepare_source(input.path, source_file.path)
          source_image = identify(source_file.path)
          validate_prepared_source!(source_image)

          crop = center_crop(source_image.width, source_image.height)
          Tempfile.create([ "legacy-display", ".jpg" ], binmode: true) do |display_file|
            build_display(source_file.path, display_file.path, crop)
            validate_display!(display_file.path)
            crop_data = crop_data_for(crop, source_image)
            validate_generated_pair!(source_file, display_file, crop_data)

            prepared_source_blob = nil
            display_blob = nil
            unless dry_run
              prepared_source_blob = upload(source_file, role: :source)
              display_blob = upload(display_file, role: :display)
            end
            crop_data = crop_data.merge("sourceBlobId" => prepared_source_blob&.id)

            @transferred = true
            return Result.new(
              source_blob: prepared_source_blob,
              display_blob: display_blob,
              crop_data: crop_data,
              input_width: input_image.width,
              input_height: input_image.height,
              source_width: source_image.width,
              source_height: source_image.height,
              enlarged: source_image.width * source_image.height > oriented_pixel_count(input_image),
              reduced: source_image.width * source_image.height < oriented_pixel_count(input_image)
            )
          end
        end
      end
    rescue ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError,
           MiniMagick::Error, MiniMagick::Invalid => error
      raise InvalidImageError, "legacy image could not be prepared (#{error.class.name})"
    ensure
      cleanup_pending_blobs unless @transferred
    end

    private

    SourceImage = Data.define(:format, :width, :height, :orientation)
    Crop = Data.define(:x, :y, :width, :height)

    def validate_legacy_blob!
      unless @legacy_blob.is_a?(ActiveStorage::Blob) && @legacy_blob.persisted? &&
          @legacy_blob.byte_size.between?(1, MAX_INPUT_BYTES) && @legacy_blob.service.exist?(@legacy_blob.key)
        raise InvalidImageError, "legacy blob is missing or exceeds the byte limit"
      end
    end

    def identify(path)
      output = MiniMagick.identify(timeout: PROCESSING_TIMEOUT_SECONDS) do |command|
        apply_resource_limits(command)
        command.format("%m\n%w\n%h\n%[orientation]")
        command << "#{path}[0]"
      end
      format, width, height, orientation = output.lines.map(&:strip)
      SourceImage.new(
        format: format.to_s.upcase,
        width: Integer(width),
        height: Integer(height),
        orientation: orientation.presence || "Undefined"
      )
    rescue TypeError, ArgumentError
      raise InvalidImageError, "image dimensions could not be identified"
    end

    def validate_input!(image)
      unless SUPPORTED_FORMATS.include?(image.format) && image.width.positive? && image.height.positive? &&
          image.width <= MAX_INPUT_DIMENSION && image.height <= MAX_INPUT_DIMENSION &&
          image.width * image.height <= MAX_INPUT_PIXELS &&
          [ image.width.fdiv(image.height), image.height.fdiv(image.width) ].max <= MAX_INPUT_ASPECT_RATIO
        raise InvalidImageError, "legacy image format or dimensions are unsupported"
      end
    end

    def prepare_source(input_path, output_path)
      input_image = identify(input_path)
      target_width, target_height = prepared_dimensions(input_image)
      validate_prepared_dimensions!(target_width, target_height)

      MiniMagick.convert(timeout: PROCESSING_TIMEOUT_SECONDS) do |command|
        apply_resource_limits(command)
        command << "#{input_path}[0]"
        command.auto_orient
        # The legacy display may be smaller than the future output. Enlarge
        # only when needed, preserving the whole image and its aspect ratio.
        command.resize("#{target_width}x#{target_height}!")
        command.background("white")
        command.alpha("remove")
        command.alpha("off")
        command.colorspace("sRGB")
        command.strip
        command.quality(SOURCE_QUALITY.to_s)
        command << "JPEG:#{output_path}"
      end
    end

    def prepared_dimensions(image)
      width, height = oriented_dimensions(image)
      required_scale = [ @output_width.fdiv(width), @output_height.fdiv(height) ].max
      maximum_scale = [
        MAX_SOURCE_DIMENSION.fdiv(width),
        MAX_SOURCE_DIMENSION.fdiv(height),
        Math.sqrt(MAX_SOURCE_PIXELS.fdiv(width * height))
      ].min
      if required_scale > maximum_scale
        raise InvalidImageError, "legacy image cannot meet the minimum dimensions within source limits"
      end

      scale = [ [ 1.0, required_scale ].max, maximum_scale ].min
      [ [ @output_width, (width * scale).floor ].max, [ @output_height, (height * scale).floor ].max ]
    end

    def oriented_dimensions(image)
      if image.orientation.in?(%w[LeftTop RightTop RightBottom LeftBottom])
        [ image.height, image.width ]
      else
        [ image.width, image.height ]
      end
    end

    def validate_prepared_dimensions!(width, height)
      return if width <= MAX_SOURCE_DIMENSION && height <= MAX_SOURCE_DIMENSION && width * height <= MAX_SOURCE_PIXELS

      raise InvalidImageError, "legacy image cannot be enlarged within source limits"
    end

    def validate_prepared_source!(image)
      unless image.format == "JPEG" && image.width >= @output_width && image.height >= @output_height &&
          image.width <= MAX_SOURCE_DIMENSION && image.height <= MAX_SOURCE_DIMENSION &&
          image.width * image.height <= MAX_SOURCE_PIXELS
        raise InvalidImageError, "prepared source does not meet minimum dimensions"
      end
    end

    def center_crop(source_width, source_height)
      ratio_width, ratio_height = RATIOS.fetch(@ratio_key)
      unit = [ source_width / ratio_width, source_height / ratio_height ].min
      width = unit * ratio_width
      height = unit * ratio_height
      Crop.new(
        x: (source_width - width) / 2,
        y: (source_height - height) / 2,
        width: width,
        height: height
      )
    end

    def build_display(source_path, output_path, crop)
      MiniMagick.convert(timeout: PROCESSING_TIMEOUT_SECONDS) do |command|
        apply_resource_limits(command)
        command << "JPEG:#{source_path}"
        command.crop("#{crop.width}x#{crop.height}+#{crop.x}+#{crop.y}")
        command.resize("#{@output_width}x#{@output_height}!")
        command.strip
        command.quality(DISPLAY_QUALITY.to_s)
        command << "JPEG:#{output_path}"
      end
    end

    def validate_display!(path)
      image = identify(path)
      return if image.format == "JPEG" && image.width == @output_width && image.height == @output_height

      raise InvalidImageError, "display image dimensions are invalid"
    end

    def validate_generated_pair!(source_file, display_file, crop_data)
      source_file.rewind
      display_file.rewind
      PairValidator.new(purpose: @purpose).call(
        source: Upload.new(tempfile: source_file, content_type: PairValidator::JPEG_CONTENT_TYPE),
        display: Upload.new(tempfile: display_file, content_type: PairValidator::JPEG_CONTENT_TYPE),
        crop_data:
      )
    rescue PairValidator::Invalid => error
      raise InvalidImageError, "generated image pair is invalid (#{error.class.name})"
    end

    def upload(file, role:)
      file.rewind
      blob = @blob_upload_service.new(
        record: @record,
        purpose: @purpose_name,
        role:,
        upload: Upload.new(tempfile: file, content_type: PairValidator::JPEG_CONTENT_TYPE)
      ).call
      @pending_blobs << blob
      blob
    rescue StagedBlobUploadService::UploadFailedError => error
      raise UploadFailedError, "prepared blob upload failed (#{error.class.name})"
    rescue StandardError => error
      raise UploadFailedError, "prepared blob upload failed (#{error.class.name})"
    end

    def crop_data_for(crop, source_image)
      {
        "schemaVersion" => 1,
        "ratioKey" => @ratio_key,
        "source" => { "width" => source_image.width, "height" => source_image.height },
        "crop" => { "x" => crop.x, "y" => crop.y, "width" => crop.width, "height" => crop.height },
        "zoom" => source_image.width.fdiv(crop.width).round(4),
        "output" => {
          "width" => @output_width,
          "height" => @output_height,
          "mimeType" => "image/jpeg",
          "quality" => 0.9
        }
      }
    end

    def cleanup_pending_blobs
      @pending_blobs.each do |blob|
        StagedBlobPurgeService.new(blob:).call
      rescue ActiveRecord::RecordNotFound
        nil
      rescue StandardError => error
        Rails.logger.error("[ImageAttachments::LegacyPairBuilder] staged blob cleanup failed blob=#{blob.id} error=#{error.class.name}")
      end
    end

    def apply_resource_limits(command)
      command.limit("memory", NormalizeService::MEMORY_LIMIT)
      command.limit("map", NormalizeService::MAP_LIMIT)
      command.limit("disk", NormalizeService::DISK_LIMIT)
      command.limit("thread", NormalizeService::THREAD_LIMIT.to_s)
      command.limit("width", MAX_INPUT_DIMENSION.to_s)
      command.limit("height", MAX_INPUT_DIMENSION.to_s)
    end

    def oriented_pixel_count(image)
      width, height = oriented_dimensions(image)
      width * height
    end
  end
end
