# frozen_string_literal: true

require "test_helper"

class ImageAttachments::LegacyPairBuilderTest < ActiveSupport::TestCase
  setup do
    @blob_ids = []
    @store = Store.create!(name: "Legacy Builder Store")
    @legacy_blob = upload_fixture("sample.png", "image/png")
  end

  teardown do
    @blob_ids.reverse_each do |id|
      blob = ActiveStorage::Blob.find_by(id:)
      next unless blob

      if ImageAttachments::StagedBlobMetadata.owned?(blob)
        ImageAttachments::StagedBlobPurgeService.new(blob:).call
      else
        blob.purge
      end
    end
  end

  test "creates validated independent staged source and centered social display" do
    result = build_pair(record: @store, purpose: :thumbnail)

    assert_not_equal @legacy_blob.id, result.source_blob.id
    assert_not_equal @legacy_blob.key, result.source_blob.key
    assert_not_equal result.source_blob.key, result.display_blob.key
    assert result.source_blob.service.exist?(result.source_blob.key)
    assert result.display_blob.service.exist?(result.display_blob.key)
    assert_equal "image/jpeg", result.source_blob.content_type
    assert_equal "image/jpeg", result.display_blob.content_type
    assert ImageAttachments::StagedBlobMetadata.owned?(result.source_blob, purpose: :thumbnail, role: :source)
    assert ImageAttachments::StagedBlobMetadata.owned?(result.display_blob, purpose: :thumbnail, role: :display)
    assert_equal [ 48, 32 ], [ result.input_width, result.input_height ]
    assert_equal [ 1200, 800 ], [ result.source_width, result.source_height ]
    assert result.enlarged
    assert_not result.reduced
    assert_equal [ 1200, 630 ], dimensions(result.display_blob)
    assert_equal({ "x" => 0, "y" => 85, "width" => 1200, "height" => 630 }, result.crop_data.fetch("crop"))
    assert_equal result.source_blob.id, result.crop_data.fetch("sourceBlobId")
    assert_equal 1.0, result.crop_data.fetch("zoom")
  end

  test "creates four independent blobs for avatar and cover from one legacy blob" do
    user = create_user
    avatar = build_pair(record: user, purpose: :avatar)
    cover = build_pair(record: user, purpose: :cover)

    assert_equal 4, [ avatar.source_blob, avatar.display_blob, cover.source_blob, cover.display_blob ].map(&:key).uniq.size
    assert_equal [ 1536, 1024 ], dimensions(avatar.source_blob)
    assert_equal [ 1024, 1024 ], dimensions(avatar.display_blob)
    assert_equal({ "x" => 256, "y" => 0, "width" => 1024, "height" => 1024 }, avatar.crop_data.fetch("crop"))
    assert_equal 1.5, avatar.crop_data.fetch("zoom")
    assert_equal [ 1200, 800 ], dimensions(cover.source_blob)
    assert_equal [ 1200, 630 ], dimensions(cover.display_blob)
  end

  test "re-encodes a suitable JPEG so metadata and original bytes are not retained" do
    large = generated_image("1600x900", "JPEG", "gradient:red-blue")
    legacy = upload_file(large, "large.jpg", "image/jpeg")

    result = build_pair(record: @store, purpose: :thumbnail, legacy_blob: legacy)

    assert_equal [ 1600, 900 ], dimensions(result.source_blob)
    assert_not_equal legacy.checksum, result.source_blob.checksum
    assert_equal({ "x" => 0, "y" => 30, "width" => 1600, "height" => 840 }, result.crop_data.fetch("crop"))
    assert_not result.enlarged
    assert_not result.reduced
  ensure
    large&.close!
  end

  test "shrinks a large legacy image to the 4096 pixel and 8 megapixel editing source limits" do
    large = generated_image("5000x2000", "JPEG", "navy")
    legacy = upload_file(large, "large-source.jpg", "image/jpeg")

    result = build_pair(record: @store, purpose: :thumbnail, legacy_blob: legacy)

    assert_equal [ 4096, 1638 ], dimensions(result.source_blob)
    assert_operator result.source_width * result.source_height, :<=, 8_000_000
    assert result.reduced
    assert_not result.enlarged
    assert_equal [ 1200, 630 ], dimensions(result.display_blob)
  ensure
    large&.close!
  end

  test "auto-orients the editing source and strips orientation metadata" do
    rotated = Tempfile.new([ "legacy-rotated", ".png" ])
    MiniMagick.convert do |command|
      command.size("630x1200")
      command << "gradient:red-blue"
      command.set("orientation", "RightTop")
      command << "PNG:#{rotated.path}"
    end
    rotated.binmode
    rotated.rewind
    legacy = upload_file(rotated, "rotated.png", "image/png")

    result = build_pair(record: @store, purpose: :thumbnail, legacy_blob: legacy)

    assert_equal [ 1200, 630 ], dimensions(result.source_blob)
    assert_includes %w[Undefined TopLeft], image_property(result.source_blob, "%[orientation]")
  ensure
    rotated&.close!
  end

  test "flattens transparency onto white and writes the editing source as sRGB" do
    transparent = Tempfile.new([ "legacy-transparent", ".png" ])
    MiniMagick.convert do |command|
      command.size("1200x630")
      command << "xc:none"
      command.fill("red")
      command.draw("rectangle 100,100 1100,530")
      command << "PNG:#{transparent.path}"
    end
    transparent.binmode
    transparent.rewind
    legacy = upload_file(transparent, "transparent.png", "image/png")

    result = build_pair(record: @store, purpose: :thumbnail, legacy_blob: legacy)

    assert_equal "sRGB", image_property(result.source_blob, "%[colorspace]")
    assert_match(/255/, image_property(result.source_blob, "%[pixel:p{0,0}]"))
  ensure
    transparent&.close!
  end

  test "leaves no generated blobs when a legacy image is corrupt" do
    corrupt = upload_fixture("corrupt.heic", "image/heic")

    assert_no_difference("ActiveStorage::Blob.count") do
      assert_raises(described_class::InvalidImageError) do
        build_pair(record: @store, purpose: :thumbnail, legacy_blob: corrupt, track: false)
      end
    end
  end

  test "rejects an unknown purpose before creating blobs" do
    assert_raises(ArgumentError) do
      described_class.new(record: @store, purpose: :avatar, legacy_blob: @legacy_blob)
    end
  end

  test "dry run performs full validation without creating staged blobs" do
    result = nil
    assert_no_difference("ActiveStorage::Blob.count") do
      result = described_class.new(
        record: @store,
        purpose: :thumbnail,
        legacy_blob: @legacy_blob
      ).call(dry_run: true)
    end

    assert_nil result.source_blob
    assert_nil result.display_blob
    assert_nil result.crop_data.fetch("sourceBlobId")
    assert_equal [ 1200, 800 ], [ result.source_width, result.source_height ]
    assert_equal [ 1200, 630 ], result.crop_data.fetch("output").values_at("width", "height")
    assert result.enlarged
    assert_not result.reduced
  end

  test "rejects a legacy image whose minimum output and editing source limits conflict" do
    narrow = generated_image("100x600", "JPEG", "gradient:red-blue")
    legacy = upload_file(narrow, "too-narrow.jpg", "image/jpeg")

    assert_no_difference("ActiveStorage::Blob.count") do
      assert_raises(described_class::InvalidImageError) do
        described_class.new(record: @store, purpose: :thumbnail, legacy_blob: legacy).call(dry_run: true)
      end
    end
  ensure
    narrow&.close!
  end

  test "purges the staged source blob when display upload fails" do
    builder = described_class.new(record: @store, purpose: :thumbnail, legacy_blob: @legacy_blob)
    original_upload = builder.method(:upload)
    failure_class = described_class::UploadFailedError
    upload_count = 0
    builder.define_singleton_method(:upload) do |file, role:|
      upload_count += 1
      raise failure_class, "controlled display failure" if role == :display

      original_upload.call(file, role:)
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

  def build_pair(record:, purpose:, legacy_blob: @legacy_blob, track: true)
    result = described_class.new(record:, purpose:, legacy_blob:).call
    track_blobs(result.source_blob, result.display_blob) if track
    result
  end

  def create_user
    User.create!(
      email: "legacy-builder-#{SecureRandom.hex(4)}@example.com",
      password: "password",
      role: :customer
    )
  end

  def generated_image(size, format, color)
    file = Tempfile.new([ "legacy-generated", ".#{format.downcase}" ])
    MiniMagick.convert do |command|
      command.size(size)
      command << (color.start_with?("gradient:") ? color : "xc:#{color}")
      command << "#{format}:#{file.path}"
    end
    file.binmode
    file.rewind
    file
  end

  def upload_fixture(filename, content_type)
    File.open(file_fixture(filename), "rb") do |io|
      upload_file(io, filename, content_type)
    end
  end

  def upload_file(io, filename, content_type)
    io.rewind
    blob = ActiveStorage::Blob.create_and_upload!(io:, filename:, content_type:, identify: false)
    track_blobs(blob)
    blob
  end

  def dimensions(blob)
    blob.open do |file|
      MiniMagick::Image.open(file.path).then { |image| [ image.width, image.height ] }
    end
  end

  def image_property(blob, format)
    blob.open do |file|
      MiniMagick.identify do |command|
        command.format(format)
        command << file.path
      end.strip
    end
  end

  def track_blobs(*blobs)
    @blob_ids.concat(blobs.map(&:id))
  end
end
