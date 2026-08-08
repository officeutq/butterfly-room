# frozen_string_literal: true

require "test_helper"

class ImageAttachments::RemediateServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @store = Store.create!(name: "Remediation Store")
    @old_blob = attach(
      @store.thumbnail,
      fixture: "sample.heic",
      filename: "legacy.heif",
      content_type: "image/heic"
    )
    @old_attachment_id = @store.thumbnail.attachment.id
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "reports an eligible target without changing storage by default" do
    result = nil

    assert_no_difference([ "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ]) do
      result = remediation_service.call
    end

    assert result.dry_run
    assert_equal "eligible", result.status
    assert_equal @old_attachment_id, result.attachment_id
    assert_equal @old_blob.id, result.blob_id
    assert_equal "HEIF", result.actual_format
    assert result.stored
    assert result.convertible
    assert_equal @old_blob.id, @store.reload.thumbnail.blob.id
  end

  test "normalizes one expected attachment and purges the old blob after commit" do
    result = nil

    perform_enqueued_jobs do
      result = remediation_service(apply: true).call
    end

    @store.reload
    assert_not result.dry_run
    assert_equal "normalized", result.status
    assert_equal @old_attachment_id, result.expected_attachment_id
    assert_equal @old_blob.id, result.expected_blob_id
    assert_not_equal @old_blob.id, result.blob_id
    assert_equal @store.thumbnail.blob.id, result.blob_id
    assert_equal "legacy.jpg", @store.thumbnail.filename.to_s
    assert_equal "image/jpeg", @store.thumbnail.content_type
    assert_equal "JPEG", result.actual_format
    assert_equal "\xFF\xD8".b, @store.thumbnail.download.first(2)
    assert_not ActiveStorage::Blob.exists?(@old_blob.id)
  end

  test "skips a repeated run after the attachment is already normalized" do
    remediation_service(apply: true).call
    normalized_blob = @store.reload.thumbnail.blob
    result = nil

    assert_no_difference([ "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ]) do
      result = remediation_service(apply: true).call
    end

    assert_not result.dry_run
    assert_equal "skipped_already_normalized", result.status
    assert_equal normalized_blob.id, result.blob_id
    assert_equal normalized_blob.id, @store.reload.thumbnail.blob.id
  end

  test "does not overwrite a different non-JPEG attachment" do
    newer_blob = attach(
      @store.thumbnail,
      fixture: "sample.heic",
      filename: "newer.heic",
      content_type: "image/heic"
    )

    assert_no_difference("ActiveStorage::Blob.count") do
      assert_raises(ImageAttachments::RemediateService::StaleTargetError) do
        remediation_service(apply: true).call
      end
    end

    assert_equal newer_blob.id, @store.reload.thumbnail.blob.id
  end

  test "rejects unsupported record and attachment pairs" do
    error = assert_raises(ArgumentError) do
      described_service.new(
        record_type: "Store",
        record_id: @store.id,
        attachment_name: "avatar",
        expected_attachment_id: @old_attachment_id,
        expected_blob_id: @old_blob.id
      )
    end

    assert_includes error.message, "supported display image"
  end

  private

  def described_service
    ImageAttachments::RemediateService
  end

  def remediation_service(apply: false)
    described_service.new(
      record_type: "Store",
      record_id: @store.id,
      attachment_name: "thumbnail",
      expected_attachment_id: @old_attachment_id,
      expected_blob_id: @old_blob.id,
      apply:
    )
  end

  def attach(attachment, fixture:, filename:, content_type:)
    File.open(file_fixture(fixture), "rb") do |io|
      attachment.attach(io:, filename:, content_type:, identify: false)
    end
    attachment.blob
  end
end
