# frozen_string_literal: true

require "test_helper"

class ImageAttachments::LegacyPairBuilderTest < ActiveSupport::TestCase
  setup do
    @blob_ids = []
    @legacy_blob = upload_fixture("sample.png", "image/png")
  end

  teardown do
    @blob_ids.each do |id|
      blob = ActiveStorage::Blob.find_by(id: id)
      blob&.purge unless blob&.attachments&.exists?
    end
  end

  test "creates independent enlarged source and centered social display without loading the whole blob in Ruby" do
    result = build_pair("social")

    assert_not_equal @legacy_blob.id, result.source_blob.id
    assert_not_equal @legacy_blob.key, result.source_blob.key
    assert_not_equal result.source_blob.key, result.display_blob.key
    assert result.source_blob.service.exist?(result.source_blob.key)
    assert result.display_blob.service.exist?(result.display_blob.key)
    assert_equal "image/jpeg", result.source_blob.content_type
    assert_equal "image/jpeg", result.display_blob.content_type
    assert_equal [ 48, 32 ], [ result.input_width, result.input_height ]
    assert_equal [ 1200, 800 ], [ result.source_width, result.source_height ]
    assert result.enlarged
    assert_equal [ 1200, 630 ], dimensions(result.display_blob)
    assert_equal({ "x" => 0, "y" => 85, "width" => 1200, "height" => 630 }, result.crop_data.fetch("crop"))
    assert_equal result.source_blob.id, result.crop_data.fetch("sourceBlobId")
    assert_equal 1.0, result.crop_data.fetch("zoom")
  end

  test "creates independent source blobs and deterministic crops for avatar and cover from one legacy blob" do
    avatar = build_pair("square")
    cover = build_pair("social")

    assert_equal 4, [ avatar.source_blob, avatar.display_blob, cover.source_blob, cover.display_blob ].map(&:key).uniq.size
    assert_equal [ 1536, 1024 ], dimensions(avatar.source_blob)
    assert_equal [ 1024, 1024 ], dimensions(avatar.display_blob)
    assert_equal({ "x" => 256, "y" => 0, "width" => 1024, "height" => 1024 }, avatar.crop_data.fetch("crop"))
    assert_equal 1.5, avatar.crop_data.fetch("zoom")
    assert_equal [ 1200, 800 ], dimensions(cover.source_blob)
    assert_equal [ 1200, 630 ], dimensions(cover.display_blob)
  end

  test "does not shrink a legacy image that already meets the minimum dimensions" do
    large = Tempfile.new([ "legacy-large", ".jpg" ])
    MiniMagick.convert do |command|
      command.size("1600x900")
      command << "gradient:red-blue"
      command << "JPEG:#{large.path}"
    end
    legacy = upload_file(large, "large.jpg", "image/jpeg")

    result = described_class.new(source_blob: legacy, ratio_key: "social").call
    track(result.source_blob, result.display_blob)

    assert_equal [ 1600, 900 ], dimensions(result.source_blob)
    assert_equal legacy.checksum, result.source_blob.checksum
    assert_equal({ "x" => 0, "y" => 30, "width" => 1600, "height" => 840 }, result.crop_data.fetch("crop"))
    assert_not result.enlarged
  ensure
    large&.close!
  end

  test "leaves no generated blobs when a legacy image is corrupt" do
    corrupt = upload_fixture("corrupt.heic", "image/heic")

    assert_no_difference("ActiveStorage::Blob.count") do
      assert_raises(described_class::InvalidImageError) do
        described_class.new(source_blob: corrupt, ratio_key: "social").call
      end
    end
  end

  test "rejects an unknown ratio before creating blobs" do
    assert_raises(ArgumentError) { described_class.new(source_blob: @legacy_blob, ratio_key: "wide") }
  end

  test "dry run performs conversion checks and reports the plan without creating blobs" do
    result = nil
    assert_no_difference("ActiveStorage::Blob.count") do
      result = described_class.new(source_blob: @legacy_blob, ratio_key: "social").call(dry_run: true)
    end

    assert_nil result.source_blob
    assert_nil result.display_blob
    assert_nil result.crop_data.fetch("sourceBlobId")
    assert_equal [ 1200, 800 ], [ result.source_width, result.source_height ]
    assert_equal [ 1200, 630 ], result.crop_data.fetch("output").values_at("width", "height")
    assert result.enlarged
  end

  test "enlarges a narrow image when only one input dimension is below the output" do
    narrow = Tempfile.new([ "legacy-narrow", ".jpg" ])
    MiniMagick.convert do |command|
      command.size("100x600")
      command << "gradient:red-blue"
      command << "JPEG:#{narrow.path}"
    end
    legacy = upload_file(narrow, "narrow.jpg", "image/jpeg")

    result = described_class.new(source_blob: legacy, ratio_key: "social").call
    track(result.source_blob, result.display_blob)

    assert_equal [ 1200, 7200 ], dimensions(result.source_blob)
    assert_equal [ 1200, 630 ], dimensions(result.display_blob)
    assert result.enlarged
  ensure
    narrow&.close!
  end

  test "rejects enlargement that would exceed the editing source limits" do
    narrow = Tempfile.new([ "legacy-too-narrow", ".jpg" ])
    MiniMagick.convert do |command|
      command.size("100x800")
      command << "gradient:red-blue"
      command << "JPEG:#{narrow.path}"
    end
    legacy = upload_file(narrow, "too-narrow.jpg", "image/jpeg")

    assert_no_difference("ActiveStorage::Blob.count") do
      assert_raises(described_class::InvalidImageError) do
        described_class.new(source_blob: legacy, ratio_key: "social").call(dry_run: true)
      end
    end
  ensure
    narrow&.close!
  end

  test "purges the generated source blob when display upload fails" do
    builder = described_class.new(source_blob: @legacy_blob, ratio_key: "social")
    original_upload = builder.method(:upload)
    failure_class = described_class::UploadFailedError
    upload_count = 0
    builder.define_singleton_method(:upload) do |file, filename:, image:|
      upload_count += 1
      raise failure_class, "controlled display failure" if upload_count == 2

      original_upload.call(file, filename: filename, image: image)
    end

    assert_no_difference("ActiveStorage::Blob.count") do
      assert_raises(described_class::UploadFailedError) { builder.call }
    end
    assert_equal 2, upload_count
  end

  private

  def described_class
    ImageAttachments::LegacyPairBuilder
  end

  def build_pair(ratio)
    result = described_class.new(source_blob: @legacy_blob, ratio_key: ratio).call
    track(result.source_blob, result.display_blob)
    result
  end

  def upload_fixture(filename, content_type)
    File.open(file_fixture(filename), "rb") do |io|
      upload_file(io, filename, content_type)
    end
  end

  def upload_file(io, filename, content_type)
    io.rewind
    blob = ActiveStorage::Blob.create_and_upload!(io: io, filename: filename, content_type: content_type, identify: false)
    track(blob)
    blob
  end

  def dimensions(blob)
    blob.open do |file|
      MiniMagick::Image.open(file.path).then { |image| [ image.width, image.height ] }
    end
  end

  def track(*blobs)
    @blob_ids.concat(blobs.map(&:id))
  end
end
