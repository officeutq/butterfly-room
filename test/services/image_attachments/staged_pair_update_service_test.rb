# frozen_string_literal: true

require "test_helper"

class ImageAttachments::StagedPairUpdateServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @blob_ids = []
    @records = []
    @record = create_user
    @old_source = attach(@record.avatar_source, blob)
    @old_display = attach(@record.avatar, blob)
    @record.update!(avatar_crop_data: crop_data(@old_source))
  end

  teardown do
    @records.each { |record| record.destroy! if record.persisted? }
    clear_enqueued_jobs
    clear_performed_jobs
    @blob_ids.each do |id|
      stored_blob = ActiveStorage::Blob.find_by(id:)
      stored_blob&.purge unless stored_blob&.attachments&.exists?
    end
  end

  test "replace updates source display crop data and normal attributes then purges replaced blobs" do
    expected = snapshot
    new_source = staged_blob(:source)
    new_display = staged_blob(:display)

    perform_enqueued_jobs do
      service(
        operation: :replace,
        expected:,
        new_source_blob: new_source,
        new_display_blob: new_display,
        attributes: { bio: "画像と同時更新" }
      ).call
    end

    @record.reload
    assert_equal new_source.id, @record.avatar_source.blob.id
    assert_equal new_display.id, @record.avatar.blob.id
    assert_equal new_source.id, @record.avatar_crop_data.fetch("sourceBlobId")
    assert_equal "画像と同時更新", @record.bio
    assert_not ImageAttachments::StagedBlobMetadata.owned?(new_source.reload)
    assert_not ImageAttachments::StagedBlobMetadata.owned?(new_display.reload)
    assert_not ActiveStorage::Blob.exists?(@old_source.id)
    assert_not ActiveStorage::Blob.exists?(@old_display.id)
  end

  test "replace creates a complete pair when the purpose has no current image" do
    empty_record = create_user
    expected = snapshot(empty_record)
    new_source = staged_blob(:source)
    new_display = staged_blob(:display)

    service(
      record: empty_record,
      operation: :replace,
      expected:,
      new_source_blob: new_source,
      new_display_blob: new_display
    ).call

    empty_record.reload
    assert_equal new_source.id, empty_record.avatar_source.blob.id
    assert_equal new_display.id, empty_record.avatar.blob.id
    assert_equal new_source.id, empty_record.avatar_crop_data.fetch("sourceBlobId")
  end

  test "replace follows the configured source display and crop fields for every social purpose" do
    store = Store.create!(name: "pair-store-#{SecureRandom.hex(6)}")
    booth = Booth.create!(store:, name: "pair-booth")
    @records.push(store, booth)
    cases = [
      [ create_user, :cover ],
      [ store, :thumbnail ],
      [ booth, :thumbnail ]
    ]

    cases.each do |record, purpose_name|
      purpose = record.image_attachment_purpose_for(purpose_name)
      expected = described_class.capture(record:, purpose: purpose_name)
      source = staged_blob(:source, record:, purpose: purpose_name)
      display = staged_blob(:display, record:, purpose: purpose_name)

      described_class.new(
        record:,
        purpose: purpose_name,
        operation: :replace,
        expected_snapshot: expected,
        crop_data: social_crop_data(source),
        new_source_blob: source,
        new_display_blob: display
      ).call

      record.reload
      assert_equal source.id, record.public_send(purpose.source_attachment).blob.id
      assert_equal display.id, record.public_send(purpose.display_attachment).blob.id
      assert_equal source.id, record.public_send(purpose.crop_attribute).fetch("sourceBlobId")
    end
  end

  test "reedit keeps source and changes only display and crop data" do
    expected = snapshot
    new_display = staged_blob(:display)
    edited_crop = crop_data(@old_source).deep_merge(
      "crop" => { "x" => 128, "y" => 0, "width" => 768, "height" => 768 },
      "zoom" => 1.3333,
      "sourceBlobId" => 999_999
    )

    perform_enqueued_jobs do
      service(
        operation: :reedit,
        expected:,
        new_display_blob: new_display,
        crop: edited_crop
      ).call
    end

    @record.reload
    assert_equal @old_source.id, @record.avatar_source.blob.id
    assert_equal new_display.id, @record.avatar.blob.id
    assert_equal @old_source.id, @record.avatar_crop_data.fetch("sourceBlobId")
    assert_equal 1.3333, @record.avatar_crop_data.fetch("zoom")
    assert_not ActiveStorage::Blob.exists?(@old_display.id)
  end

  test "delete removes source display and crop data in one transaction" do
    expected = snapshot

    perform_enqueued_jobs do
      service(operation: :delete, expected:, crop: nil).call
    end

    @record.reload
    assert_not @record.avatar_source.attached?
    assert_not @record.avatar.attached?
    assert_equal({}, @record.avatar_crop_data)
    assert_not ActiveStorage::Blob.exists?(@old_source.id)
    assert_not ActiveStorage::Blob.exists?(@old_display.id)
  end

  test "explicit rollback keeps old pair and synchronously purges only staged blobs" do
    expected = snapshot
    new_source = staged_blob(:source)
    new_display = staged_blob(:display)

    assert_raises(described_class::TransactionRolledBackError) do
      service(
        operation: :replace,
        expected:,
        new_source_blob: new_source,
        new_display_blob: new_display
      ).call do
        raise ActiveRecord::Rollback
      end
    end

    assert_old_pair
    assert_not ActiveStorage::Blob.exists?(new_source.id)
    assert_not ActiveStorage::Blob.exists?(new_display.id)
  end

  test "record validation failure rolls back pair attributes and staged blobs" do
    expected = snapshot
    new_source = staged_blob(:source)
    new_display = staged_blob(:display)

    assert_raises(ActiveRecord::RecordInvalid) do
      service(
        operation: :replace,
        expected:,
        new_source_blob: new_source,
        new_display_blob: new_display,
        attributes: { email: "" }
      ).call
    end

    assert_old_pair
    assert_not ActiveStorage::Blob.exists?(new_source.id)
    assert_not ActiveStorage::Blob.exists?(new_display.id)
  end

  test "block failure rolls back related records and image pair" do
    expected = snapshot
    new_source = staged_blob(:source)
    new_display = staged_blob(:display)
    store_name = "pair-related-#{SecureRandom.hex(6)}"

    assert_raises(RuntimeError) do
      service(
        operation: :replace,
        expected:,
        new_source_blob: new_source,
        new_display_blob: new_display
      ).call do
        Store.create!(name: store_name)
        raise "controlled related record failure"
      end
    end

    assert_not Store.exists?(name: store_name)
    assert_old_pair
    assert_not ActiveStorage::Blob.exists?(new_source.id)
    assert_not ActiveStorage::Blob.exists?(new_display.id)
  end

  test "stale snapshot keeps the competing image pair and purges staged blob" do
    expected = snapshot
    competing_display = attach(@record.avatar, blob)
    staged_display = staged_blob(:display)

    assert_raises(described_class::StalePairError) do
      service(operation: :reedit, expected:, new_display_blob: staged_display).call
    end

    @record.reload
    assert_equal @old_source.id, @record.avatar_source.blob.id
    assert_equal competing_display.id, @record.avatar.blob.id
    assert_not ActiveStorage::Blob.exists?(staged_display.id)
  end

  test "missing source or display object keeps old pair and removes staged blob rows" do
    %i[source display].each do |missing_role|
      expected = snapshot
      staged_source = staged_blob(:source)
      staged_display = staged_blob(:display)
      missing = missing_role == :source ? staged_source : staged_display
      missing.service.delete(missing.key)

      assert_raises(described_class::InvalidStagedBlobError) do
        service(
          operation: :replace,
          expected:,
          new_source_blob: staged_source,
          new_display_blob: staged_display
        ).call
      end

      assert_old_pair
      assert_not ActiveStorage::Blob.exists?(staged_source.id)
      assert_not ActiveStorage::Blob.exists?(staged_display.id)
    end
  end

  test "does not purge a replaced blob still attached to another record" do
    other = create_user
    attach(other.avatar, @old_display)
    other_source = attach(other.avatar_source, blob)
    other.update!(avatar_crop_data: crop_data(other_source))
    expected = snapshot

    perform_enqueued_jobs do
      service(
        operation: :reedit,
        expected:,
        new_display_blob: staged_blob(:display)
      ).call
    end

    assert ActiveStorage::Blob.exists?(@old_display.id)
    assert_equal @old_display.id, other.reload.avatar.blob.id
  end

  test "invalid crop keeps old pair and purges staged display" do
    expected = snapshot
    staged_display = staged_blob(:display)

    assert_raises(described_class::InvalidCropDataError) do
      service(
        operation: :reedit,
        expected:,
        new_display_blob: staged_display,
        crop: { "schemaVersion" => 99 }
      ).call
    end

    assert_old_pair
    assert_not ActiveStorage::Blob.exists?(staged_display.id)
  end

  test "reedit refuses crop dimensions that do not match current source state" do
    expected = snapshot
    staged_display = staged_blob(:display)
    mismatched = crop_data(@old_source).deep_merge(
      "source" => { "width" => 1200, "height" => 1200 },
      "crop" => { "width" => 1024, "height" => 1024 },
      "zoom" => 1.1719
    )

    assert_raises(described_class::InvalidCropDataError) do
      service(operation: :reedit, expected:, new_display_blob: staged_display, crop: mismatched).call
    end

    assert_old_pair
    assert_not ActiveStorage::Blob.exists?(staged_display.id)
  end

  test "unowned expired and already attached staged blobs are refused without unsafe deletion" do
    unowned = blob
    expired = staged_blob(:display, cleanup_after: 1.minute.ago)
    attached = staged_blob(:display)
    other = create_user
    attach(other.cover_image, attached)

    [ unowned, expired, attached ].each do |candidate|
      assert_raises(described_class::InvalidStagedBlobError) do
        service(operation: :reedit, expected: snapshot, new_display_blob: candidate).call
      end
    end

    assert ActiveStorage::Blob.exists?(unowned.id)
    assert_not ActiveStorage::Blob.exists?(expired.id)
    assert ActiveStorage::Blob.exists?(attached.id)
    assert_old_pair
  end

  private

  def described_class
    ImageAttachments::StagedPairUpdateService
  end

  def create_user
    record = User.create!(
      email: "pair-#{SecureRandom.hex(8)}@example.com",
      password: "password",
      role: :customer
    )
    @records << record
    record
  end

  def blob
    File.open(file_fixture("sample.jpg"), "rb") do |io|
      stored_blob = ActiveStorage::Blob.create_and_upload!(
        io:,
        filename: "pair.jpg",
        content_type: "image/jpeg",
        identify: false
      )
      @blob_ids << stored_blob.id
      stored_blob
    end
  end

  def staged_blob(role, cleanup_after: 1.hour.from_now, record: @record, purpose: :avatar)
    blob.tap do |stored_blob|
      ImageAttachments::StagedBlobMetadata.mark!(
        stored_blob,
        purpose: record.image_attachment_purpose_for(purpose),
        role:,
        cleanup_after:
      )
    end
  end

  def attach(attachment, stored_blob)
    attachment.attach(stored_blob)
    stored_blob
  end

  def snapshot(record = @record)
    described_class.capture(record:, purpose: :avatar)
  end

  def service(
    operation:,
    expected:,
    record: @record,
    new_display_blob: nil,
    new_source_blob: nil,
    crop: :default,
    attributes: {}
  )
    source = new_source_blob || (record.avatar_source.blob if record.avatar_source.attached?)
    crop = crop_data(source) if crop == :default && operation != :delete
    described_class.new(
      record:,
      purpose: :avatar,
      operation:,
      expected_snapshot: expected,
      attributes:,
      crop_data: crop == :default ? nil : crop,
      new_source_blob:,
      new_display_blob:
    )
  end

  def crop_data(source_blob)
    {
      "schemaVersion" => 1,
      "ratioKey" => "square",
      "sourceBlobId" => source_blob&.id,
      "source" => { "width" => 1024, "height" => 1024 },
      "crop" => { "x" => 0, "y" => 0, "width" => 1024, "height" => 1024 },
      "zoom" => 1.0,
      "output" => { "width" => 1024, "height" => 1024, "mimeType" => "image/jpeg", "quality" => 0.9 }
    }
  end

  def social_crop_data(source_blob)
    {
      "schemaVersion" => 1,
      "ratioKey" => "social",
      "sourceBlobId" => source_blob.id,
      "source" => { "width" => 1200, "height" => 630 },
      "crop" => { "x" => 0, "y" => 0, "width" => 1200, "height" => 630 },
      "zoom" => 1.0,
      "output" => { "width" => 1200, "height" => 630, "mimeType" => "image/jpeg", "quality" => 0.9 }
    }
  end

  def assert_old_pair
    @record.reload
    assert_equal @old_source.id, @record.avatar_source.blob.id
    assert_equal @old_display.id, @record.avatar.blob.id
    assert_equal @old_source.id, @record.avatar_crop_data.fetch("sourceBlobId")
  end
end
