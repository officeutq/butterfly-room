# frozen_string_literal: true

require "mini_magick"
require "digest"

module ImageUploadVerifications
  class ImageValidator
    class Invalid < StandardError; end

    BYTE_LIMITS = { "source" => 20.megabytes, "display" => 5.megabytes }.freeze
    OUTPUTS = { "square" => [ 1024, 1024 ], "social" => [ 1200, 630 ] }.freeze
    MAX_PIXELS = 32_000_000
    MAX_EDGE = 8192

    def self.crop!(data)
      raise Invalid, "クロップ情報が不正です。" unless data.is_a?(Hash) && data.to_json.bytesize <= 4.kilobytes

      output = OUTPUTS[data["ratioKey"]]
      raise Invalid, "未対応のクロップ情報です。" unless data["schemaVersion"] == 1 && output

      source, crop = data.values_at("source", "crop")
      raise Invalid, "クロップ情報が不正です。" unless source.is_a?(Hash) && crop.is_a?(Hash)

      width, height = source.values_at("width", "height")
      unless [ width, height ].all? { |v| v.is_a?(Integer) && v.between?(1, MAX_EDGE) } &&
          width * height <= MAX_PIXELS && [ width.fdiv(height), height.fdiv(width) ].max <= 8 &&
          width >= output[0] && height >= output[1]
        raise Invalid, "編集元の寸法が暫定上限・最低寸法の範囲外です。"
      end

      x, y, w, h = crop.values_at("x", "y", "width", "height")
      unless [ x, y, w, h, data["zoom"] ].all? { |v| v.is_a?(Numeric) && v.finite? } &&
          x >= 0 && y >= 0 && w > 0 && h > 0 && x + w <= width + 0.001 && y + h <= height + 0.001 &&
          (w * output[1] - h * output[0]).abs <= 1 && (data["zoom"] - width / w).abs <= 0.001
        raise Invalid, "クロップ範囲・倍率が不正です。"
      end
      expected_output = { "width" => output[0], "height" => output[1], "mimeType" => "image/jpeg", "quality" => 0.9 }
      raise Invalid, "表示用画像の設定が不正です。" unless data["output"] == expected_output

      # Store only schema fields, never arbitrary client metadata.
      data.slice("schemaVersion", "ratioKey", "zoom").merge(
        "source" => source.slice("width", "height"), "crop" => crop.slice("x", "y", "width", "height"),
        "output" => expected_output
      )
    end

    def self.call(file, role:, crop_data:)
      limit = BYTE_LIMITS.fetch(role)
      bytes = File.size(file.path)
      raise Invalid, "#{role}の容量は1byte〜#{limit / 1.megabyte}MiBです。" unless bytes.between?(1, limit)
      raise Invalid, "実体がJPEGではありません。" unless File.binread(file.path, 3) == "\xFF\xD8\xFF".b

      expected = role == "source" ? crop_data.fetch("source").values_at("width", "height") : OUTPUTS.fetch(crop_data.fetch("ratioKey"))
      header = MiniMagick.identify(timeout: 5) do |command|
        limits(command)
        command.ping
        command.format("%m %w %h %n")
        command << "JPEG:#{file.path}"
      end
      expected_header = [ "JPEG", *expected.map(&:to_s), "1" ]
      raise Invalid, "#{role}の実寸法・画像数がクロップ情報と一致しません。" unless header.split == expected_header

      # Force the JPEG decoder, enforce resources and decode all pixels. No
      # recompression: the browser's source/display bytes are preserved exactly.
      result = MiniMagick.convert(timeout: 20) do |command|
        limits(command)
        command.regard_warnings
        command << "JPEG:#{file.path}"
        command.format("%m %w %h %n")
        command << "info:"
      end
      unless result.split == expected_header
        raise Invalid, "#{role}の実寸法・画像数がクロップ情報と一致しません。"
      end
      { width: expected[0], height: expected[1], bytes: bytes, mime_type: "image/jpeg", sha256: Digest::SHA256.file(file.path).hexdigest }
    rescue MiniMagick::Error, MiniMagick::Invalid
      raise Invalid, "JPEGの実体検査に失敗しました（破損・寸法・処理上限）。"
    end

    def self.limits(command)
      command.limit("memory", "128MiB")
      command.limit("map", "256MiB")
      command.limit("disk", "512MiB")
      command.limit("thread", "1")
      command.limit("width", MAX_EDGE.to_s)
      command.limit("height", MAX_EDGE.to_s)
    end
    private_class_method :limits
  end
end
