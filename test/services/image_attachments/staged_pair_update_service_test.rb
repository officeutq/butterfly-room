# frozen_string_literal: true

require "test_helper"

class ImagePairPrototypeRecord < ImageUploadVerificationRun
  has_one_attached :prototype_source
  has_one_attached :prototype_display
end

class ImageAttachments::StagedPairUpdateServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @blob_ids = []
    @records = []
    @user = User.create!(email: "pair-prototype@example.com", password: "password", role: :system_admin)
    @record = create_record
    @old_source = attach(@record.prototype_source, blob)
    @old_display = attach(@record.prototype_display, blob)
    @record.update!(crop_data: crop_data(@old_source))
  end

  teardown do
    @records.each(&:destroy!)
    clear_enqueued_jobs
    clear_performed_jobs
    @blob_ids.each do |id|
      stored_blob = ActiveStorage::Blob.find_by(id: id)
      stored_blob&.purge unless stored_blob&.attachments&.exists?
    end
  end

  test "replaces source display and crop data in one transaction then purges replaced blobs" do
    expected = snapshot
    new_source = blob
    new_display = blob

    perform_enqueued_jobs { service(expected:, new_source_blob: new_source, new_display_blob: new_display).call }

    @record.reload
    assert_equal new_source.id, @record.prototype_source.blob.id
    assert_equal new_display.id, @record.prototype_display.blob.id
    assert_equal new_source.id, @record.crop_data.fetch("sourceBlobId")
    assert_not ActiveStorage::Blob.exists?(@old_source.id)
    assert_not ActiveStorage::Blob.exists?(@old_display.id)
  end

  test "re-edit keeps the editing source and updates only display and crop data" do
    expected = snapshot
    new_display = blob
    edited_crop = crop_data(@old_source).merge("zoom" => 1.25)

    perform_enqueued_jobs do
      service(expected:, new_display_blob: new_display, crop: edited_crop).call
    end

    @record.reload
    assert_equal @old_source.id, @record.prototype_source.blob.id
    assert_equal new_display.id, @record.prototype_display.blob.id
    assert_equal @old_source.id, @record.crop_data.fetch("sourceBlobId")
    assert_equal 1.25, @record.crop_data.fetch("zoom")
    assert_not ActiveStorage::Blob.exists?(@old_display.id)
  end

  test "transaction failure keeps the old pair and purges only staged blobs" do
    expected = snapshot
    new_source = blob
    new_display = blob

    assert_raises(described_class::TransactionRolledBackError) do
      service(expected:, new_source_blob: new_source, new_display_blob: new_display).call do
        raise ActiveRecord::Rollback
      end
    end

    @record.reload
    assert_equal @old_source.id, @record.prototype_source.blob.id
    assert_equal @old_display.id, @record.prototype_display.blob.id
    assert_equal @old_source.id, @record.crop_data.fetch("sourceBlobId")
    assert_not ActiveStorage::Blob.exists?(new_source.id)
    assert_not ActiveStorage::Blob.exists?(new_display.id)
  end

  test "related record validation failure rolls back pair and crop data" do
    expected = snapshot
    new_source = blob
    new_display = blob

    assert_raises(ActiveRecord::RecordInvalid) do
      service(expected:, new_source_blob: new_source, new_display_blob: new_display).call do |record|
        record.errors.add(:base, "controlled related record failure")
        raise ActiveRecord::RecordInvalid, record
      end
    end

    @record.reload
    assert_equal @old_source.id, @record.prototype_source.blob.id
    assert_equal @old_display.id, @record.prototype_display.blob.id
    assert_equal @old_source.id, @record.crop_data.fetch("sourceBlobId")
    assert_not ActiveStorage::Blob.exists?(new_source.id)
    assert_not ActiveStorage::Blob.exists?(new_display.id)
  end

  test "stale snapshot keeps a concurrent image pair and purges staged blobs" do
    expected = snapshot
    concurrent_display = attach(@record.prototype_display, blob)
    staged_display = blob

    assert_raises(described_class::StalePairError) do
      service(expected:, new_display_blob: staged_display).call
    end

    assert_equal concurrent_display.id, @record.reload.prototype_display.blob.id
    assert_equal @old_source.id, @record.prototype_source.blob.id
    assert_not ActiveStorage::Blob.exists?(staged_display.id)
  end

  test "missing staged object keeps the old pair and cleans all staged blob rows" do
    expected = snapshot
    staged_source = blob
    staged_display = blob
    staged_display.service.delete(staged_display.key)

    assert_raises(described_class::InvalidStagedBlobError) do
      service(expected:, new_source_blob: staged_source, new_display_blob: staged_display).call
    end

    @record.reload
    assert_equal @old_source.id, @record.prototype_source.blob.id
    assert_equal @old_display.id, @record.prototype_display.blob.id
    assert_not ActiveStorage::Blob.exists?(staged_source.id)
    assert_not ActiveStorage::Blob.exists?(staged_display.id)
  end

  test "does not purge a replaced blob that is still attached to another record" do
    other = create_record
    attach(other.prototype_display, @old_display)
    attach(other.prototype_source, blob)
    other.update!(crop_data: crop_data(other.prototype_source.blob))
    expected = snapshot

    perform_enqueued_jobs do
      service(expected:, new_display_blob: blob).call
    end

    assert ActiveStorage::Blob.exists?(@old_display.id)
    assert_equal @old_display.id, other.reload.prototype_display.blob.id
  end

  test "invalid crop schema keeps old pair and cleans staged blobs" do
    expected = snapshot
    staged_display = blob

    assert_raises(described_class::InvalidCropDataError) do
      service(expected:, new_display_blob: staged_display, crop: { "schemaVersion" => 99 }).call
    end

    assert_equal @old_display.id, @record.reload.prototype_display.blob.id
    assert_not ActiveStorage::Blob.exists?(staged_display.id)
  end

  private

  def described_class
    ImageAttachments::StagedPairUpdateService
  end

  def create_record
    record = ImagePairPrototypeRecord.create!(
      user: @user,
      transport: "multipart",
      state: "complete",
      crop_data: {},
      expires_at: 1.hour.from_now,
      cleanup_after: 2.hours.from_now
    )
    @records << record
    record
  end

  def blob
    File.open(file_fixture("sample.jpg"), "rb") do |io|
      stored_blob = ActiveStorage::Blob.create_and_upload!(
        io: io,
        filename: "prototype.jpg",
        content_type: "image/jpeg",
        identify: false
      )
      @blob_ids << stored_blob.id
      stored_blob
    end
  end

  def attach(attachment, stored_blob)
    attachment.attach(stored_blob)
    stored_blob
  end

  def snapshot
    described_class.capture(
      record: @record,
      source_attachment_name: :prototype_source,
      display_attachment_name: :prototype_display
    )
  end

  def service(expected:, new_display_blob:, new_source_blob: nil, crop: nil)
    described_class.new(
      record: @record,
      source_attachment_name: :prototype_source,
      display_attachment_name: :prototype_display,
      crop_attribute: :crop_data,
      crop_data: crop || crop_data(new_source_blob || @record.prototype_source.blob),
      expected_snapshot: expected,
      new_source_blob: new_source_blob,
      new_display_blob: new_display_blob
    )
  end

  def crop_data(source_blob)
    {
      "schemaVersion" => 1,
      "ratioKey" => "square",
      "sourceBlobId" => source_blob.id,
      "source" => { "width" => 1024, "height" => 1024 },
      "crop" => { "x" => 0, "y" => 0, "width" => 1024, "height" => 1024 },
      "zoom" => 1.0,
      "output" => { "width" => 1024, "height" => 1024, "mimeType" => "image/jpeg", "quality" => 0.9 }
    }
  end
end
