# frozen_string_literal: true

require "mini_magick"
require "tempfile"

module ImageAttachments
  class NormalizeService
    CONTENT_TYPE = "image/jpeg"
    DEFAULT_QUALITY = 94
    DEFAULT_MAX_SOURCE_PIXELS = 60_000_000
    DEFAULT_PROCESSING_TIMEOUT_SECONDS = 30
    MAX_SOURCE_DIMENSION = 16_384
    MEMORY_LIMIT = "256MiB"
    MAP_LIMIT = "512MiB"
    DISK_LIMIT = "1GiB"
    THREAD_LIMIT = 2
    SUPPORTED_FORMATS = %w[JPEG PNG WEBP HEIC HEIF].freeze

    Result = Struct.new(:io, :filename, :content_type, keyword_init: true)
    SourceImage = Struct.new(:format, :width, :height, keyword_init: true)

    class InvalidImageError < StandardError; end
    class UnsupportedFormatError < InvalidImageError; end
    class SourceImageTooLargeError < InvalidImageError; end

    def initialize(
      upload:,
      max_width:,
      max_height:,
      quality: DEFAULT_QUALITY,
      max_source_pixels: DEFAULT_MAX_SOURCE_PIXELS,
      processing_timeout_seconds: DEFAULT_PROCESSING_TIMEOUT_SECONDS
    )
      @upload = upload
      @max_width = positive_integer!(max_width, :max_width)
      @max_height = positive_integer!(max_height, :max_height)
      @quality = quality_integer!(quality)
      @max_source_pixels = positive_integer!(max_source_pixels, :max_source_pixels)
      @processing_timeout_seconds = positive_integer!(processing_timeout_seconds, :processing_timeout_seconds)
    end

    def call
      raise ArgumentError, "a block is required" unless block_given?

      source_path = source_path!
      source_image = identify_source(source_path)
      unless SUPPORTED_FORMATS.include?(source_image.format)
        raise UnsupportedFormatError, "unsupported image format"
      end
      validate_source_size!(source_image)

      normalized_file = build_normalized_file
      normalized_file.binmode
      normalized_file.close

      convert_to_jpeg(source_path, normalized_file.path)
      validate_output!(normalized_file.path)

      normalized_file.open
      normalized_file.binmode
      normalized_file.rewind

      yield Result.new(
        io: normalized_file,
        filename: normalized_filename,
        content_type: CONTENT_TYPE
      )
    rescue InvalidImageError => error
      log_failure(error)
      raise
    rescue MiniMagick::Error, MiniMagick::Invalid => error
      log_failure(error)
      raise InvalidImageError, "image could not be converted to JPEG"
    ensure
      normalized_file&.close!
    end

    private

    def source_path!
      file = @upload.respond_to?(:tempfile) ? @upload.tempfile : @upload
      path = file.path if file.respond_to?(:path)

      unless path.present? && File.file?(path) && File.size?(path)
        raise InvalidImageError, "image file is missing"
      end

      path
    end

    def build_normalized_file
      Tempfile.new([ "normalized-image", ".jpg" ])
    end

    def identify_source(path)
      output = MiniMagick.identify(timeout: @processing_timeout_seconds) do |command|
        apply_resource_limits(command)
        command.format("%m %w %h")
        command << "#{path}[0]"
      end
      format, width, height = output.split

      SourceImage.new(
        format: format.to_s.upcase,
        width: Integer(width),
        height: Integer(height)
      )
    rescue TypeError, ArgumentError
      raise InvalidImageError, "image dimensions could not be identified"
    end

    def convert_to_jpeg(source_path, target_path)
      MiniMagick.convert(timeout: @processing_timeout_seconds) do |command|
        apply_resource_limits(command)
        command << "#{source_path}[0]"
        command.auto_orient
        command.resize("#{@max_width}x#{@max_height}>")
        command.background("white")
        command.alpha("remove")
        command.alpha("off")
        command.colorspace("sRGB")
        command.strip
        command.quality(@quality.to_s)
        command << "JPEG:#{target_path}"
      end
    end

    def validate_output!(path)
      unless File.size?(path) && identify_source(path).format == "JPEG"
        raise InvalidImageError, "normalized image is not JPEG"
      end
    end

    def validate_source_size!(source_image)
      if source_image.width <= 0 || source_image.height <= 0 ||
          source_image.width > MAX_SOURCE_DIMENSION || source_image.height > MAX_SOURCE_DIMENSION ||
          source_image.width * source_image.height > @max_source_pixels
        raise SourceImageTooLargeError, "source image dimensions are too large"
      end
    end

    def apply_resource_limits(command)
      command.limit("memory", MEMORY_LIMIT)
      command.limit("map", MAP_LIMIT)
      command.limit("disk", DISK_LIMIT)
      command.limit("thread", THREAD_LIMIT.to_s)
      command.limit("width", MAX_SOURCE_DIMENSION.to_s)
      command.limit("height", MAX_SOURCE_DIMENSION.to_s)
    end

    def normalized_filename
      original_filename = @upload.original_filename if @upload.respond_to?(:original_filename)
      basename = File.basename(original_filename.to_s)
      stem = File.basename(basename, File.extname(basename))
      stem = "image" if stem.blank?

      "#{stem}.jpg"
    end

    def positive_integer!(value, name)
      integer = Integer(value)
      raise ArgumentError, "#{name} must be positive" unless integer.positive?

      integer
    rescue TypeError, ArgumentError
      raise ArgumentError, "#{name} must be a positive integer"
    end

    def quality_integer!(value)
      quality = Integer(value)
      raise ArgumentError, "quality must be between 1 and 100" unless quality.between?(1, 100)

      quality
    rescue TypeError, ArgumentError
      raise ArgumentError, "quality must be an integer between 1 and 100"
    end

    def log_failure(error)
      Rails.logger.warn(
        "[ImageAttachments::NormalizeService] image normalization failed " \
        "(#{error.class.name})"
      )
    end
  end
end
