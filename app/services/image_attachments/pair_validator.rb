# frozen_string_literal: true

require "digest"
require "mini_magick"

module ImageAttachments
  class PairValidator
    class Invalid < StandardError; end

    BYTE_LIMITS = { source: 20.megabytes, display: 5.megabytes }.freeze
    OUTPUTS = { "square" => [ 1024, 1024 ], "social" => [ 1200, 630 ] }.freeze
    MAX_CROP_DATA_BYTES = 4.kilobytes
    MAX_SOURCE_PIXELS = 8_000_000
    MAX_SOURCE_EDGE = 4096
    MAX_SOURCE_ASPECT_RATIO = 8
    BOUNDS_TOLERANCE = 0.001
    RATIO_CROSS_PRODUCT_TOLERANCE = 1
    ZOOM_TOLERANCE = 0.001
    JPEG_CONTENT_TYPE = "image/jpeg"

    Result = Data.define(:crop_data, :source, :display)

    def initialize(purpose:)
      @ratio_key = purpose.ratio_key.to_s
      @output_width = Integer(purpose.output_width)
      @output_height = Integer(purpose.output_height)

      unless OUTPUTS[@ratio_key] == [ @output_width, @output_height ]
        raise ArgumentError, "unsupported image attachment purpose"
      end
    rescue NoMethodError, TypeError, ArgumentError
      raise ArgumentError, "invalid image attachment purpose"
    end

    def call(source:, display:, crop_data:)
      validated_crop_data = crop_data!(crop_data)
      Result.new(
        crop_data: validated_crop_data,
        source: image!(source, role: :source, crop_data: validated_crop_data),
        display: image!(display, role: :display, crop_data: validated_crop_data)
      )
    end

    def crop_data!(data)
      validate_crop_envelope!(data)
      source = data.fetch("source")
      crop = data.fetch("crop")
      validate_source_dimensions!(source)

      normalized_crop = validate_and_normalize_crop!(source:, crop:)
      expected_zoom = source.fetch("width").fdiv(normalized_crop.fetch("width"))
      raise Invalid, "クロップ倍率が不正です。" unless finite_number?(expected_zoom)

      expected_zoom = expected_zoom.round(4)
      zoom = data["zoom"]
      unless finite_number?(zoom) && zoom.positive? && (zoom - expected_zoom).abs <= ZOOM_TOLERANCE
        raise Invalid, "クロップ倍率が不正です。"
      end

      expected_output = {
        "width" => @output_width,
        "height" => @output_height,
        "mimeType" => JPEG_CONTENT_TYPE,
        "quality" => 0.9
      }
      raise Invalid, "表示用画像の設定が不正です。" unless data["output"] == expected_output

      {
        "schemaVersion" => 1,
        "ratioKey" => @ratio_key,
        "source" => source.slice("width", "height"),
        "crop" => normalized_crop,
        "zoom" => expected_zoom,
        "output" => expected_output
      }
    rescue KeyError, JSON::GeneratorError, SystemStackError
      raise Invalid, "クロップ情報が不正です。"
    end

    def image!(input, role:, crop_data:)
      role = role.to_sym
      limit = BYTE_LIMITS.fetch(role)
      file = extract_file!(input)
      validate_declared_content_type!(input)
      bytes = File.size(file.path)
      unless bytes.between?(1, limit)
        raise Invalid, "#{role}の容量は1byte〜#{limit / 1.megabyte}MiBです。"
      end
      raise Invalid, "実体がJPEGではありません。" unless jpeg_signature?(file.path)

      expected_dimensions = if role == :source
        crop_data.fetch("source").values_at("width", "height")
      else
        [ @output_width, @output_height ]
      end
      expected_header = [ "JPEG", *expected_dimensions.map(&:to_s), "1" ]
      raise Invalid, "#{role}の実寸法・画像数がクロップ情報と一致しません。" unless identify(file.path) == expected_header
      raise Invalid, "#{role}の実寸法・画像数がクロップ情報と一致しません。" unless decode(file.path) == expected_header

      {
        width: expected_dimensions[0],
        height: expected_dimensions[1],
        bytes:,
        mime_type: JPEG_CONTENT_TYPE,
        sha256: Digest::SHA256.file(file.path).hexdigest
      }
    rescue KeyError
      raise ArgumentError, "unknown image role: #{role}"
    rescue SystemCallError, IOError, MiniMagick::Error, MiniMagick::Invalid
      raise Invalid, "JPEGの実体検査に失敗しました（破損・寸法・処理上限）。"
    end

    private

    def validate_crop_envelope!(data)
      unless data.is_a?(Hash) && data.to_json.bytesize <= MAX_CROP_DATA_BYTES &&
          data["schemaVersion"].is_a?(Integer) && data["schemaVersion"] == 1 &&
          data["ratioKey"] == @ratio_key && data["source"].is_a?(Hash) && data["crop"].is_a?(Hash)
        raise Invalid, "未対応または不正なクロップ情報です。"
      end
    end

    def validate_source_dimensions!(source)
      width, height = source.values_at("width", "height")
      unless [ width, height ].all? { |value| value.is_a?(Integer) && value.positive? } &&
          width >= @output_width && height >= @output_height &&
          width <= MAX_SOURCE_EDGE && height <= MAX_SOURCE_EDGE &&
          width * height <= MAX_SOURCE_PIXELS &&
          [ width.fdiv(height), height.fdiv(width) ].max <= MAX_SOURCE_ASPECT_RATIO
        raise Invalid, "編集元画像の寸法が許容範囲外です。"
      end
    end

    def validate_and_normalize_crop!(source:, crop:)
      source_width, source_height = source.values_at("width", "height")
      x, y, width, height = crop.values_at("x", "y", "width", "height")
      unless [ x, y, width, height ].all? { |value| finite_number?(value) } && width.positive? && height.positive? &&
          width <= source_width && height <= source_height &&
          x >= -BOUNDS_TOLERANCE && y >= -BOUNDS_TOLERANCE &&
          x + width <= source_width + BOUNDS_TOLERANCE && y + height <= source_height + BOUNDS_TOLERANCE &&
          (width * @output_height - height * @output_width).abs <= RATIO_CROSS_PRODUCT_TOLERANCE
        raise Invalid, "クロップ範囲・比率が不正です。"
      end

      {
        "x" => normalize_axis(x, size: width, source_size: source_width),
        "y" => normalize_axis(y, size: height, source_size: source_height),
        "width" => width,
        "height" => height
      }
    end

    def normalize_axis(position, size:, source_size:)
      [ [ position, 0 ].max, source_size - size ].min
    end

    def finite_number?(value)
      value.is_a?(Numeric) && value.real? && value.finite?
    end

    def extract_file!(input)
      file = input.respond_to?(:tempfile) ? input.tempfile : input
      raise Invalid, "一時ファイルが不正です。" unless file.respond_to?(:path) && file.path.present?

      file
    end

    def validate_declared_content_type!(input)
      return unless input.respond_to?(:content_type)
      return if input.content_type == JPEG_CONTENT_TYPE

      raise Invalid, "申告MIME typeがJPEGではありません。"
    end

    def jpeg_signature?(path)
      File.open(path, "rb") { |file| file.read(3) } == "\xFF\xD8\xFF".b
    end

    def identify(path)
      output = MiniMagick.identify(timeout: 5) do |command|
        limits(command)
        command.ping
        command.format("%m %w %h %n")
        command << "JPEG:#{path}"
      end
      output.split
    end

    def decode(path)
      output = MiniMagick.convert(timeout: 20) do |command|
        limits(command)
        command.regard_warnings
        command << "JPEG:#{path}"
        command.format("%m %w %h %n")
        command << "info:"
      end
      output.split
    end

    def limits(command)
      command.limit("memory", "128MiB")
      command.limit("map", "256MiB")
      command.limit("disk", "512MiB")
      command.limit("thread", "1")
      command.limit("width", MAX_SOURCE_EDGE.to_s)
      command.limit("height", MAX_SOURCE_EDGE.to_s)
    end
  end
end
