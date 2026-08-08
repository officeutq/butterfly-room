# frozen_string_literal: true

require "test_helper"

class ImageAttachments::NormalizeServiceTest < ActiveSupport::TestCase
  UploadedFile = Struct.new(:tempfile, :original_filename, :content_type, keyword_init: true)

  test "converts HEIC binary to JPEG without trusting filename or content type" do
    with_upload(
      "sample.heic",
      original_filename: "camera-upload.png",
      content_type: "image/png"
    ) do |upload|
      normalized_path = nil

      result = service(upload).call do |normalized|
        normalized_path = normalized.io.path
        format, width, height = identify(normalized_path)

        assert_equal "JPEG", format
        assert_equal [ 24, 16 ], [ width, height ]
        assert_equal "camera-upload.jpg", normalized.filename
        assert_equal "image/jpeg", normalized.content_type
        assert_equal "\xFF\xD8".b, normalized.io.read(2)

        :persisted
      end

      assert_equal :persisted, result
      refute File.exist?(normalized_path), "normalized tempfile should be removed after the block"
    end
  end

  test "normalizes JPEG PNG and WebP inputs" do
    %w[sample.jpg sample.png sample.webp].each do |filename|
      with_upload(filename, content_type: "application/octet-stream") do |upload|
        service(upload).call do |normalized|
          format, width, height = identify(normalized.io.path)

          assert_equal "JPEG", format, filename
          assert_equal [ 24, 16 ], [ width, height ], filename
          assert_equal "image/jpeg", normalized.content_type, filename
        end
      end
    end
  end

  test "applies EXIF orientation before resizing" do
    with_upload("oriented.jpg", content_type: "image/jpeg") do |upload|
      service(upload).call do |normalized|
        _format, width, height = identify(normalized.io.path)

        assert_equal [ 12, 24 ], [ width, height ]
      end
    end
  end

  test "composites transparent pixels onto a white background" do
    with_upload("sample.png", content_type: "image/png") do |upload|
      service(upload).call do |normalized|
        rgb = pixel_rgb(normalized.io.path, x: 0, y: 0)

        assert rgb.all? { |channel| channel >= 245 }, "expected a white pixel, got #{rgb.inspect}"
      end
    end
  end

  test "rejects a corrupt upload without yielding the original file" do
    with_upload("corrupt.heic") do |upload|
      yielded = false

      assert_raises(ImageAttachments::NormalizeService::InvalidImageError) do
        service(upload).call { yielded = true }
      end

      refute yielded
    end
  end

  test "rejects a valid but unsupported image format" do
    with_upload("sample.gif", content_type: "image/gif") do |upload|
      assert_raises(ImageAttachments::NormalizeService::UnsupportedFormatError) do
        service(upload).call { flunk "unsupported input must not be yielded" }
      end
    end
  end

  test "rejects an image over the source pixel guard" do
    with_upload("sample.heic") do |upload|
      normalizer = described_service.new(
        upload:,
        max_width: 24,
        max_height: 24,
        max_source_pixels: 1_000
      )

      assert_raises(ImageAttachments::NormalizeService::SourceImageTooLargeError) do
        normalizer.call { flunk "oversized input must not be yielded" }
      end
    end
  end

  test "removes its tempfile when conversion fails" do
    with_upload("sample.heic") do |upload|
      normalized_file = Tempfile.new([ "controlled-normalized-image", ".jpg" ])
      normalized_path = normalized_file.path
      normalizer = service(upload)
      normalizer.define_singleton_method(:build_normalized_file) { normalized_file }
      normalizer.define_singleton_method(:convert_to_jpeg) do |_source_path, _target_path|
        raise MiniMagick::Error, "fixture conversion failure"
      end

      assert_raises(ImageAttachments::NormalizeService::InvalidImageError) do
        normalizer.call { flunk "failed conversion must not be yielded" }
      end

      refute File.exist?(normalized_path), "normalized tempfile should be removed after failure"
    end
  end

  test "requires a block so the normalized tempfile cannot escape its lifecycle" do
    with_upload("sample.heic") do |upload|
      assert_raises(ArgumentError) { service(upload).call }
    end
  end

  test "validates conversion options" do
    with_upload("sample.heic") do |upload|
      assert_raises(ArgumentError) do
        described_service.new(upload:, max_width: 0, max_height: 24)
      end

      assert_raises(ArgumentError) do
        described_service.new(upload:, max_width: 24, max_height: 24, quality: 101)
      end
    end
  end

  private

  def described_service
    ImageAttachments::NormalizeService
  end

  def service(upload)
    described_service.new(upload:, max_width: 24, max_height: 24, quality: 94)
  end

  def with_upload(filename, original_filename: filename, content_type: "image/heic")
    File.open(file_fixture(filename), "rb") do |file|
      upload = UploadedFile.new(tempfile: file, original_filename:, content_type:)
      yield upload
    end
  end

  def identify(path)
    output = MiniMagick.identify do |command|
      command.format("%m %w %h")
      command << "#{path}[0]"
    end
    format, width, height = output.split

    [ format, Integer(width), Integer(height) ]
  end

  def pixel_rgb(path, x:, y:)
    output = MiniMagick.convert do |command|
      command << "#{path}[0]"
      command.format("%[fx:round(255*r)],%[fx:round(255*g)],%[fx:round(255*b)]")
      command << "info:"
    end

    output.split(",").map { |channel| Integer(channel) }
  end
end
