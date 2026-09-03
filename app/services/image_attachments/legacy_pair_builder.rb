# frozen_string_literal: true

require "mini_magick"
require "tempfile"

module ImageAttachments
  # Prototype used to decide how legacy display images become independently
  # stored editing sources and deterministic initial crops. It does not attach
  # the generated blobs to production records.
  class LegacyPairBuilder
    OUTPUTS = {
      "square" => [ 1024, 1024 ],
      "social" => [ 1200, 630 ]
    }.freeze
    RATIOS = {
      "square" => [ 1, 1 ],
      "social" => [ 40, 21 ]
    }.freeze
    SUPPORTED_FORMATS = NormalizeService::SUPPORTED_FORMATS
    MAX_SOURCE_DIMENSION = 8192
    MAX_SOURCE_PIXELS = 32_000_000
    SOURCE_QUALITY = 94
    DISPLAY_QUALITY = 90
    PROCESSING_TIMEOUT_SECONDS = 30

    Result = Data.define(
      :source_blob,
      :display_blob,
      :crop_data,
      :input_width,
      :input_height,
      :source_width,
      :source_height,
      :enlarged
    )

    class Error < StandardError; end
    class InvalidImageError < Error; end
    class UploadFailedError < Error; end

    def initialize(source_blob:, ratio_key:)
      @source_blob = source_blob
      @ratio_key = ratio_key.to_s
      @output_width, @output_height = OUTPUTS.fetch(@ratio_key) do
        raise ArgumentError, "unknown ratio_key: #{@ratio_key}"
      end
      @pending_blobs = []
      @transferred = false
      @called = false
    end

    def call(dry_run: false)
      raise Error, "builder instances cannot be reused" if @called

      @called = true
      validate_source_blob!

      @source_blob.open do |input|
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

            prepared_source_blob = nil
            display_blob = nil
            unless dry_run
              prepared_source_blob = upload(source_file, filename: "source.jpg", image: source_image)
              display_blob = upload(
                display_file,
                filename: "display.jpg",
                image: SourceImage.new(
                  format: "JPEG",
                  width: @output_width,
                  height: @output_height,
                  orientation: "Undefined"
                )
              )
            end
            crop_data = crop_data_for(crop, source_image, prepared_source_blob)

            @transferred = true
            return Result.new(
              source_blob: prepared_source_blob,
              display_blob: display_blob,
              crop_data: crop_data,
              input_width: input_image.width,
              input_height: input_image.height,
              source_width: source_image.width,
              source_height: source_image.height,
              enlarged: source_image.width * source_image.height > input_image.width * input_image.height
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

    def validate_source_blob!
      unless @source_blob.is_a?(ActiveStorage::Blob) && @source_blob.persisted? && @source_blob.service.exist?(@source_blob.key)
        raise InvalidImageError, "source blob is missing"
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
          image.width <= MAX_SOURCE_DIMENSION && image.height <= MAX_SOURCE_DIMENSION &&
          image.width * image.height <= MAX_SOURCE_PIXELS
        raise InvalidImageError, "legacy image format or dimensions are unsupported"
      end
    end

    def prepare_source(input_path, output_path)
      input_image = identify(input_path)
      if exact_copy_allowed?(input_image)
        File.open(input_path, "rb") do |input|
          File.open(output_path, "wb") { |output| IO.copy_stream(input, output) }
        end
        return
      end

      target_width, target_height = prepared_dimensions(input_image)
      validate_prepared_dimensions!(target_width, target_height)

      MiniMagick.convert(timeout: PROCESSING_TIMEOUT_SECONDS) do |command|
        apply_resource_limits(command)
        command << "#{input_path}[0]"
        command.auto_orient
        # The legacy display may be smaller than the future output. Enlarge
        # only when needed, preserving the whole image and its aspect ratio.
        command.resize("#{target_width}x#{target_height}!") if target_width != input_image.width || target_height != input_image.height
        command.background("white")
        command.alpha("remove")
        command.alpha("off")
        command.colorspace("sRGB")
        command.strip
        command.quality(SOURCE_QUALITY.to_s)
        command << "JPEG:#{output_path}"
      end
    end

    def exact_copy_allowed?(image)
      image.format == "JPEG" && image.width >= @output_width && image.height >= @output_height &&
        image.orientation.in?(%w[Undefined TopLeft])
    end

    def prepared_dimensions(image)
      width, height = oriented_dimensions(image)
      scale = [ 1.0, @output_width.fdiv(width), @output_height.fdiv(height) ].max
      [ (width * scale).ceil, (height * scale).ceil ]
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
      unless image.format == "JPEG" && image.width >= @output_width && image.height >= @output_height
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

    def upload(file, filename:, image:)
      file.rewind
      blob = ActiveStorage::Blob.build_after_unfurling(
        io: file,
        filename: filename,
        content_type: "image/jpeg",
        metadata: { identified: true, analyzed: true, width: image.width, height: image.height },
        service_name: @source_blob.service_name,
        identify: false
      )
      blob.save!
      @pending_blobs << blob
      file.rewind
      blob.upload_without_unfurling(file)
      raise UploadFailedError, "prepared blob was not stored" unless blob.service.exist?(blob.key)

      blob
    rescue UploadFailedError
      raise
    rescue StandardError => error
      raise UploadFailedError, "prepared blob upload failed (#{error.class.name})"
    end

    def crop_data_for(crop, source_image, source_blob)
      {
        "schemaVersion" => 1,
        "ratioKey" => @ratio_key,
        "sourceBlobId" => source_blob&.id,
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
        blob.reload
        blob.purge unless blob.attachments.exists?
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
      command.limit("width", MAX_SOURCE_DIMENSION.to_s)
      command.limit("height", MAX_SOURCE_DIMENSION.to_s)
    end
  end
end
