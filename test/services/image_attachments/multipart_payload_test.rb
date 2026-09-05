# frozen_string_literal: true

require "test_helper"
require "tempfile"

class ImageAttachments::MultipartPayloadTest < ActiveSupport::TestCase
  setup do
    @tempfiles = []
  end

  teardown do
    @tempfiles.each(&:close!)
  end

  test "defines and parses the shared strong parameter contract" do
    upload = stub_upload
    params = ActionController::Parameters.new(
      image_pair: {
        operation: "replace",
        source: upload,
        display: upload,
        crop_data: JSON.generate(crop_data),
        expected: {
          source_attachment_id: "11",
          source_blob_id: "12",
          display_attachment_id: "13",
          display_blob_id: "14",
          ignored: "value"
        },
        ignored: "value"
      }
    )

    payload = described_class.from_params(params)

    assert_equal :replace, payload.operation
    assert_same upload, payload.source_upload
    assert_equal crop_data, payload.crop_data
    assert_equal 11, payload.expected_snapshot.source_attachment_id
    assert_equal 14, payload.expected_snapshot.display_blob_id
  end

  test "allows a server-selected root for forms with multiple image purposes" do
    params = ActionController::Parameters.new(
      avatar_image_pair: { operation: "delete", expected: empty_expected }
    )

    payload = described_class.from_params(params, root: :avatar_image_pair)

    assert_equal :delete, payload.operation
  end

  test "accepts replace reedit and delete only with their required fields" do
    upload = stub_upload
    expected = empty_expected

    replace = described_class.parse(
      operation: "replace", source: upload, display: upload,
      crop_data: crop_json, expected:
    )
    reedit = described_class.parse(
      operation: "reedit", display: upload,
      crop_data: crop_json, expected:
    )
    delete = described_class.parse(operation: "delete", expected:)

    assert_equal :replace, replace.operation
    assert_nil reedit.source_upload
    assert_nil delete.crop_data
  end

  test "rejects incomplete operations malformed crop JSON and unknown fields" do
    invalid_payloads = [
      { operation: "replace", display: stub_upload, crop_data: crop_json, expected: empty_expected },
      { operation: "reedit", source: stub_upload, display: stub_upload, crop_data: crop_json, expected: empty_expected },
      { operation: "delete", display: stub_upload, expected: empty_expected },
      { operation: "replace", source: stub_upload, display: stub_upload, crop_data: "{", expected: empty_expected },
      { operation: "replace", source: stub_upload, display: stub_upload, crop_data: "{}", expected: empty_expected, extra: true }
    ]

    invalid_payloads.each do |payload|
      assert_raises(described_class::Invalid) { described_class.parse(payload) }
    end
  end

  test "requires a complete positive attachment and blob snapshot" do
    invalid_expected_values = [
      nil,
      { source_attachment_id: "1" },
      { source_attachment_id: "0", source_blob_id: "2" },
      { source_attachment_id: 1.0, source_blob_id: 2 },
      { source_attachment_id: "1x", source_blob_id: "2" },
      { unknown: "1" }
    ]

    invalid_expected_values.each do |expected|
      assert_raises(described_class::Invalid) do
        described_class.parse(operation: "delete", expected:)
      end
    end
  end

  test "rejects crop JSON over the crop schema byte limit before parsing" do
    assert_raises(described_class::Invalid) do
      described_class.parse(
        operation: "replace",
        source: stub_upload,
        display: stub_upload,
        crop_data: JSON.generate(value: "x" * ImageAttachments::PairValidator::MAX_CROP_DATA_BYTES),
        expected: empty_expected
      )
    end
  end

  private

  def described_class
    ImageAttachments::MultipartPayload
  end

  def stub_upload
    file = Tempfile.new([ "multipart-payload", ".jpg" ]).tap { |tempfile| @tempfiles << tempfile }
    ActionDispatch::Http::UploadedFile.new(
      tempfile: file,
      filename: "image.jpg",
      type: "image/jpeg"
    )
  end

  def empty_expected
    {
      source_attachment_id: "",
      source_blob_id: "",
      display_attachment_id: "",
      display_blob_id: ""
    }
  end

  def crop_json
    JSON.generate(crop_data)
  end

  def crop_data
    { "schemaVersion" => 1 }
  end
end
