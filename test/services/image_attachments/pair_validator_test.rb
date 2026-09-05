# frozen_string_literal: true

require "test_helper"
require "mini_magick"
require "tempfile"

class ImageAttachments::PairValidatorTest < ActiveSupport::TestCase
  Invalid = ImageAttachments::PairValidator::Invalid

  setup do
    @tempfiles = []
  end

  teardown do
    @tempfiles.each(&:close!)
  end

  test "accepts and inspects valid square and social image pairs" do
    [
      [ User.image_attachment_purpose_for(:avatar), square_crop_data, [ 1600, 1200 ] ],
      [ Store.image_attachment_purpose_for(:thumbnail), social_crop_data, [ 1600, 1200 ] ]
    ].each do |purpose, crop_data, source_dimensions|
      result = validator(purpose).call(
        source: jpeg_upload(*source_dimensions),
        display: jpeg_upload(purpose.output_width, purpose.output_height),
        crop_data:
      )

      assert_equal crop_data, result.crop_data
      assert_equal source_dimensions, [ result.source.fetch(:width), result.source.fetch(:height) ]
      assert_equal [ purpose.output_width, purpose.output_height ],
        [ result.display.fetch(:width), result.display.fetch(:height) ]
      assert_equal "image/jpeg", result.source.fetch(:mime_type)
      assert_match(/\A[0-9a-f]{64}\z/, result.display.fetch(:sha256))
    end
  end

  test "accepts migration-owned tempfiles without relying on an upload MIME declaration" do
    source = jpeg_upload(1600, 1200).tempfile
    display = jpeg_upload(1200, 630).tempfile

    result = social_validator.call(source:, display:, crop_data: social_crop_data)

    assert_equal 1600, result.source.fetch(:width)
    assert_equal 1200, result.display.fetch(:width)
  end

  test "drops client blob ids and arbitrary metadata while normalizing tolerated boundary drift" do
    data = social_crop_data.deep_merge(
      "sourceBlobId" => 999,
      "ignored" => "client value",
      "source" => { "ignored" => true },
      "crop" => { "x" => -0.0005, "ignored" => true }
    )

    validated = social_validator.crop_data!(data)

    assert_equal 0, validated.dig("crop", "x")
    assert_not validated.key?("sourceBlobId")
    assert_not validated.key?("ignored")
    assert_equal %w[height width], validated.fetch("source").keys.sort
    assert_equal %w[height width x y], validated.fetch("crop").keys.sort
  end

  test "rejects unsupported schema purpose source dimensions and oversized metadata" do
    invalid_values = [
      social_crop_data.merge("schemaVersion" => 1.0),
      social_crop_data.merge("ratioKey" => "square"),
      social_crop_data.deep_merge("source" => { "width" => 1199 }),
      social_crop_data.deep_merge("source" => { "width" => 4097 }),
      social_crop_data.deep_merge("source" => { "width" => 4000, "height" => 2100 }),
      social_crop_data.merge("ignored" => "x" * 4096)
    ]

    invalid_values.each do |data|
      assert_raises(Invalid) { social_validator.crop_data!(data) }
    end
  end

  test "rejects invalid crop coordinates ratios zoom and output settings" do
    invalid_values = [
      social_crop_data.deep_merge("crop" => { "x" => -0.0011 }),
      social_crop_data.deep_merge("crop" => { "x" => 0.0011 }),
      social_crop_data.deep_merge("crop" => { "width" => 1600.001 }),
      social_crop_data.deep_merge("crop" => { "height" => 839 }),
      social_crop_data.deep_merge("crop" => { "width" => Float::MIN, "height" => Float::MIN }),
      social_crop_data.deep_merge("crop" => { "x" => Float::NAN }),
      social_crop_data.deep_merge("crop" => { "width" => Float::INFINITY }),
      social_crop_data.merge("zoom" => 1.01),
      social_crop_data.deep_merge("output" => { "quality" => 0.8 })
    ]

    invalid_values.each do |data|
      assert_raises(Invalid) { social_validator.crop_data!(data) }
    end
  end

  test "derives a canonical zoom instead of trusting insignificant client drift" do
    data = square_crop_data.merge("zoom" => 1.33325)

    assert_equal 1.3333, square_validator.crop_data!(data).fetch("zoom")
  end

  test "rejects declared MIME mismatches disguised formats and corrupt JPEGs" do
    display = jpeg_upload(1200, 630)
    invalid_sources = [
      jpeg_upload(1600, 1200, content_type: "image/png"),
      image_upload(1600, 1200, format: "PNG", content_type: "image/jpeg"),
      image_upload(1600, 1200, format: "WEBP", content_type: "image/jpeg"),
      corrupt_jpeg_upload
    ]

    invalid_sources.each do |source|
      assert_raises(Invalid) do
        social_validator.call(source:, display:, crop_data: social_crop_data)
      end
    end
  end

  test "rejects mismatched source and display dimensions" do
    assert_raises(Invalid) do
      social_validator.call(
        source: jpeg_upload(1200, 630),
        display: jpeg_upload(1200, 630),
        crop_data: social_crop_data
      )
    end
    assert_raises(Invalid) do
      social_validator.call(
        source: jpeg_upload(1600, 1200),
        display: jpeg_upload(1024, 1024),
        crop_data: social_crop_data
      )
    end
  end

  test "checks source and display file size limits before decoding and never creates storage records" do
    assert_no_difference([ "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ]) do
      assert_raises(Invalid) { social_validator.image!(oversized_upload(20.megabytes + 1), role: :source, crop_data: social_crop_data) }
      assert_raises(Invalid) { social_validator.image!(oversized_upload(5.megabytes + 1), role: :display, crop_data: social_crop_data) }
    end
  end

  test "rejects an invalid purpose contract" do
    purpose = Struct.new(:ratio_key, :output_width, :output_height).new("social", 1024, 1024)

    assert_raises(ArgumentError) { validator(purpose) }
  end

  private

  def validator(purpose)
    ImageAttachments::PairValidator.new(purpose:)
  end

  def social_validator
    validator(Store.image_attachment_purpose_for(:thumbnail))
  end

  def square_validator
    validator(User.image_attachment_purpose_for(:avatar))
  end

  def social_crop_data
    crop_data(
      ratio_key: "social",
      source: [ 1600, 1200 ],
      crop: { "x" => 0, "y" => 180, "width" => 1600, "height" => 840 },
      zoom: 1
    )
  end

  def square_crop_data
    crop_data(
      ratio_key: "square",
      source: [ 1600, 1200 ],
      crop: { "x" => 200, "y" => 0, "width" => 1200, "height" => 1200 },
      zoom: 1.3333
    )
  end

  def crop_data(ratio_key:, source:, crop:, zoom:)
    width, height = ImageAttachments::PairValidator::OUTPUTS.fetch(ratio_key)
    {
      "schemaVersion" => 1,
      "ratioKey" => ratio_key,
      "source" => { "width" => source[0], "height" => source[1] },
      "crop" => crop,
      "zoom" => zoom,
      "output" => {
        "width" => width,
        "height" => height,
        "mimeType" => "image/jpeg",
        "quality" => 0.9
      }
    }
  end

  def jpeg_upload(width, height, content_type: "image/jpeg")
    image_upload(width, height, format: "JPEG", content_type:)
  end

  def image_upload(width, height, format:, content_type:)
    file = tempfile("pair-validator", ".#{format.downcase}")
    MiniMagick.convert do |command|
      command.size("#{width}x#{height}")
      command << "gradient:red-blue"
      command << "#{format}:#{file.path}"
    end
    file.binmode
    file.rewind
    uploaded_file(file, content_type:)
  end

  def corrupt_jpeg_upload
    file = tempfile("corrupt", ".jpg")
    file.binmode
    file.write("\xFF\xD8\xFFbroken".b)
    file.rewind
    uploaded_file(file, content_type: "image/jpeg")
  end

  def oversized_upload(bytes)
    file = tempfile("oversized", ".jpg")
    file.binmode
    file.write("\xFF\xD8\xFF".b)
    file.truncate(bytes)
    file.rewind
    uploaded_file(file, content_type: "image/jpeg")
  end

  def uploaded_file(file, content_type:)
    ActionDispatch::Http::UploadedFile.new(
      tempfile: file,
      filename: File.basename(file.path),
      type: content_type
    )
  end

  def tempfile(basename, extension)
    Tempfile.new([ basename, extension ]).tap { |file| @tempfiles << file }
  end
end
