# frozen_string_literal: true

require "test_helper"

class ImageAttachments::LegacyMigrationServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @tracked_blob_ids = []
    @user = create_user
    @store = Store.create!(name: "Legacy Migration Store")
    @booth = Booth.create!(store: @store, name: "Legacy Migration Booth")
    @user_legacy = attach_fixture(@user.avatar, "sample.png", "user-legacy.png", "image/png")
    @store_legacy = attach_fixture(@store.thumbnail, "sample.png", "store-legacy.png", "image/png")
    @booth_legacy = attach_fixture(@booth.thumbnail_image, "sample.png", "booth-legacy.png", "image/png")
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    @tracked_blob_ids.reverse_each do |id|
      blob = ActiveStorage::Blob.find_by(id:)
      blob&.purge
    end
  end

  test "dry run validates every target and both user purposes without changing records or blobs" do
    original_snapshots = pair_snapshots
    result = nil

    assert_no_difference([ "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ]) do
      result = described_class.new.call
    end

    assert result.dry_run
    assert_equal 3, result.target_count
    assert_equal 3, result.selected_count
    assert_equal 4, result.entries.size
    assert_equal({ "eligible" => 4 }, result.status_counts)
    assert_equal original_snapshots, pair_snapshots

    user_entries = result.entries.select { |entry| entry.record_type == "User" }
    assert_equal %w[cover avatar], user_entries.map(&:purpose)
    assert_equal [ @user.avatar.attachment.id ], user_entries.map(&:legacy_attachment_id).uniq
    assert_equal [ @user_legacy.id ], user_entries.map(&:legacy_blob_id).uniq
    assert_equal [ [ 1200, 630 ], [ 1024, 1024 ] ], user_entries.map { |entry| [ entry.output_width, entry.output_height ] }
  end

  test "apply migrates all targets and creates independent validated image pairs" do
    result = migrate_all

    assert_not result.dry_run
    assert_equal({ "migrated" => 4 }, result.status_counts)
    assert_equal %w[cover avatar], result.entries.select { |entry| entry.record_type == "User" }.map(&:purpose)
    assert_equal [ @user_legacy.id ], result.entries.select { |entry| entry.record_type == "User" }.map(&:legacy_blob_id).uniq

    current_blobs = [
      @user.reload.avatar_source.blob,
      @user.avatar.blob,
      @user.cover_image_source.blob,
      @user.cover_image.blob,
      @store.reload.thumbnail_source.blob,
      @store.thumbnail.blob,
      @booth.reload.thumbnail_image_source.blob,
      @booth.thumbnail_image.blob
    ].flatten
    assert_equal 8, current_blobs.map(&:key).uniq.size
    assert_empty current_blobs.map(&:id) & [ @user_legacy.id, @store_legacy.id, @booth_legacy.id ]
    current_blobs.each { |blob| assert_not ImageAttachments::StagedBlobMetadata.owned?(blob) }

    assert_valid_pair(@user, :avatar, [ 1024, 1024 ])
    assert_valid_pair(@user, :cover, [ 1200, 630 ])
    assert_valid_pair(@store, :thumbnail, [ 1200, 630 ])
    assert_valid_pair(@booth, :thumbnail, [ 1200, 630 ])
  end

  test "repeated apply skips only complete pairs without creating duplicate blobs" do
    migrate_all
    result = nil

    assert_no_difference([ "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ]) do
      result = migrate_all
    end

    assert_equal({ "skipped_migrated" => 4 }, result.status_counts)
  end

  test "does not synthesize a cover when the avatar was already replaced by the new form" do
    commit_only_avatar(@user, @user_legacy)
    current_avatar_blob_id = @user.reload.avatar.blob.id
    result = nil

    assert_no_difference([ "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ]) do
      result = described_class.new(record_type: "User", record_id: @user.id).call
    end

    assert_equal %w[skipped_no_legacy_source skipped_migrated], result.entries.map(&:status)
    assert_not @user.reload.cover_image.attached?
    assert_equal current_avatar_blob_id, @user.avatar.blob.id
  end

  test "partial store state fails without overwriting any existing attachment" do
    partial_source = attach_fixture(@store.thumbnail_source, "sample.jpg", "partial-source.jpg", "image/jpeg")
    legacy_attachment_id = @store.thumbnail.attachment.id
    result = described_class.new(record_type: "Store", record_id: @store.id).call

    assert_equal({ "failed_partial_state" => 1 }, result.status_counts)
    assert_equal @store_legacy.id, @store.reload.thumbnail.blob.id
    assert_equal partial_source.id, @store.thumbnail_source.blob.id
    assert_equal legacy_attachment_id, @store.thumbnail.attachment.id
    assert_equal({}, @store.thumbnail_crop_data)
  end

  test "partial user cover blocks avatar migration so the common legacy origin remains available" do
    attach_fixture(@user.cover_image_source, "sample.jpg", "partial-cover-source.jpg", "image/jpeg")
    legacy_attachment_id = @user.avatar.attachment.id

    result = migrate_all
    user_entries = result.entries.select { |entry| entry.record_type == "User" }

    assert_equal %w[failed_partial_state failed_blocked_by_cover], user_entries.map(&:status)
    assert_equal @user_legacy.id, @user.reload.avatar.blob.id
    assert_equal legacy_attachment_id, @user.avatar.attachment.id
    assert_not @user.avatar_source.attached?
  end

  test "reports a corrupt target and continues with later attachments" do
    @store.thumbnail.purge
    corrupt = attach_fixture(@store.thumbnail, "corrupt.heic", "corrupt.heic", "image/heic")

    result = described_class.new.call
    entries = result.entries.group_by(&:record_type)

    assert_equal "failed_invalid_image", entries.fetch("Store").first.status
    assert_equal corrupt.id, entries.fetch("Store").first.legacy_blob_id
    assert entries.fetch("Booth").all? { |entry| entry.status == "eligible" }
  end

  test "a record without a legacy image is not selected or mutated" do
    empty_store = Store.create!(name: "Empty Legacy Migration Store")
    result = nil

    assert_no_difference([ "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ]) do
      result = described_class.new(record_type: "Store", record_id: empty_store.id).call
    end

    assert_equal 0, result.target_count
    assert_equal 0, result.selected_count
    assert_empty result.entries
    assert_empty result.status_counts
  end

  test "a user cover upload failure is cleaned and blocks avatar while other targets continue" do
    builder_factory = Object.new
    failure_class = ImageAttachments::LegacyPairBuilder::UploadFailedError
    builder_factory.define_singleton_method(:new) do |**options|
      builder = ImageAttachments::LegacyPairBuilder.new(**options)
      if options.fetch(:record).is_a?(User) && options.fetch(:purpose) == :cover
        original_upload = builder.method(:upload)
        builder.define_singleton_method(:upload) do |file, role:|
          raise failure_class, "controlled display failure" if role == :display

          original_upload.call(file, role:)
        end
      end
      builder
    end

    result = described_class.new(
      apply: true,
      confirmation: described_class::APPLY_CONFIRMATION,
      max_attachment_id: ActiveStorage::Attachment.maximum(:id),
      limit: 100,
      builder_class: builder_factory
    ).call
    user_entries = result.entries.select { |entry| entry.record_type == "User" }

    assert_equal %w[failed_upload failed_blocked_by_cover], user_entries.map(&:status)
    assert_equal "migrated", result.entries.find { |entry| entry.record_type == "Store" }.status
    assert_equal "migrated", result.entries.find { |entry| entry.record_type == "Booth" }.status
    assert_equal @user_legacy.id, @user.reload.avatar.blob.id
    assert_not @user.avatar_source.attached?
    assert_not @user.cover_image_source.attached?
    assert_empty ActiveStorage::Blob.all.select { |blob| ImageAttachments::StagedBlobMetadata.owned?(blob) }
  end

  test "supports bounded attachment id ranges and after attachment id resume" do
    first = described_class.new(limit: 1).call
    second = described_class.new(limit: 1, after_attachment_id: first.last_attachment_id).call

    assert_equal 1, first.selected_count
    assert_equal 1, second.selected_count
    assert_operator second.last_attachment_id, :>, first.last_attachment_id
    assert_not_equal first.entries.first.record_id, second.entries.first.record_id

    only_store = described_class.new(
      min_attachment_id: @store.thumbnail.attachment.id,
      max_attachment_id: @store.thumbnail.attachment.id
    ).call
    assert_equal [ "Store" ], only_store.entries.map(&:record_type).uniq
  end

  test "explicit expected ids reject a changed target" do
    result = described_class.new(
      record_type: "Store",
      record_id: @store.id,
      expected_attachment_id: @store.thumbnail.attachment.id,
      expected_blob_id: @store_legacy.id + 10_000
    ).call

    assert_equal({ "failed_conflict" => 1 }, result.status_counts)
    assert_equal @store_legacy.id, @store.reload.thumbnail.blob.id
  end

  test "a concurrent display replacement is detected and staged blobs are cleaned" do
    replacement = upload_fixture_blob("sample.jpg", "newer.jpg", "image/jpeg")
    changed = false
    builder_factory = Object.new
    builder_factory.define_singleton_method(:new) do |**options|
      builder = ImageAttachments::LegacyPairBuilder.new(**options)
      wrapper = Object.new
      wrapper.define_singleton_method(:call) do |dry_run:|
        result = builder.call(dry_run:)
        unless dry_run || changed
          options.fetch(:record).thumbnail.attach(replacement)
          changed = true
        end
        result
      end
      wrapper
    end

    before_blob_ids = ActiveStorage::Blob.pluck(:id)
    result = described_class.new(
      apply: true,
      confirmation: described_class::APPLY_CONFIRMATION,
      record_type: "Store",
      record_id: @store.id,
      limit: 1,
      expected_attachment_id: @store.thumbnail.attachment.id,
      expected_blob_id: @store_legacy.id,
      builder_class: builder_factory
    ).call

    assert_equal({ "failed_conflict" => 1 }, result.status_counts)
    assert_equal replacement.id, @store.reload.thumbnail.blob.id
    staged = ActiveStorage::Blob.where.not(id: before_blob_ids).select do |blob|
      ImageAttachments::StagedBlobMetadata.owned?(blob)
    end
    assert_empty staged
  end

  test "a transaction failure keeps the legacy pair and purges generated staged blobs" do
    updater_factory = Object.new
    updater_factory.define_singleton_method(:capture) do |**options|
      ImageAttachments::StagedPairUpdateService.capture(**options)
    end
    updater_factory.define_singleton_method(:new) do |**_options|
      Object.new.tap do |updater|
        updater.define_singleton_method(:call) do
          raise ImageAttachments::StagedPairUpdateService::TransactionRolledBackError,
            "controlled transaction failure"
        end
      end
    end

    before_blob_ids = ActiveStorage::Blob.pluck(:id)
    result = described_class.new(
      apply: true,
      confirmation: described_class::APPLY_CONFIRMATION,
      record_type: "Store",
      record_id: @store.id,
      limit: 1,
      expected_attachment_id: @store.thumbnail.attachment.id,
      expected_blob_id: @store_legacy.id,
      pair_update_service: updater_factory
    ).call

    assert_equal({ "failed_save" => 1 }, result.status_counts)
    assert_equal @store_legacy.id, @store.reload.thumbnail.blob.id
    assert_not @store.thumbnail_source.attached?
    staged = ActiveStorage::Blob.where.not(id: before_blob_ids).select do |blob|
      ImageAttachments::StagedBlobMetadata.owned?(blob)
    end
    assert_empty staged
  end

  test "apply requires a bounded scope and exact confirmation" do
    error = assert_raises(ArgumentError) { described_class.new(apply: true) }
    assert_equal "limit is required when apply is enabled", error.message

    error = assert_raises(ArgumentError) do
      described_class.new(apply: true, limit: 10, max_attachment_id: 100)
    end
    assert_includes error.message, described_class::APPLY_CONFIRMATION

    error = assert_raises(ArgumentError) do
      described_class.new(
        apply: true,
        confirmation: described_class::APPLY_CONFIRMATION,
        record_type: "Store",
        record_id: @store.id,
        limit: 1
      )
    end
    assert_equal "expected IDs are required for a record-scoped apply", error.message
  end

  private

  def described_class
    ImageAttachments::LegacyMigrationService
  end

  def migrate_all
    described_class.new(
      apply: true,
      confirmation: described_class::APPLY_CONFIRMATION,
      max_attachment_id: ActiveStorage::Attachment.maximum(:id),
      limit: 100
    ).call
  end

  def commit_only_avatar(user, legacy_blob)
    result = ImageAttachments::LegacyPairBuilder.new(
      record: user,
      purpose: :avatar,
      legacy_blob:
    ).call
    ImageAttachments::StagedPairUpdateService.new(
      record: user,
      purpose: :avatar,
      operation: :replace,
      expected_snapshot: ImageAttachments::StagedPairUpdateService.capture(record: user, purpose: :avatar),
      crop_data: result.crop_data,
      new_source_blob: result.source_blob,
      new_display_blob: result.display_blob
    ).call
    track_blobs(result.source_blob, result.display_blob)
  end

  def assert_valid_pair(record, purpose_name, output_dimensions)
    purpose = record.image_attachment_purpose_for(purpose_name)
    source = record.public_send(purpose.source_attachment)
    display = record.public_send(purpose.display_attachment)
    crop_data = record.public_send(purpose.crop_attribute)

    assert source.attached?
    assert display.attached?
    assert_not_equal source.blob.id, display.blob.id
    assert_equal source.blob.id, crop_data.fetch("sourceBlobId")
    assert_equal output_dimensions, dimensions(display.blob)
    assert_equal "image/jpeg", source.blob.content_type
    assert_equal "image/jpeg", display.blob.content_type
  end

  def pair_snapshots
    [
      snapshot(@user, :avatar),
      snapshot(@user, :cover),
      snapshot(@store, :thumbnail),
      snapshot(@booth, :thumbnail)
    ]
  end

  def snapshot(record, purpose_name)
    purpose = record.image_attachment_purpose_for(purpose_name)
    [
      record.public_send(purpose.source_attachment).attachment&.id,
      record.public_send(purpose.display_attachment).attachment&.id,
      record.public_send(purpose.crop_attribute).deep_dup
    ]
  end

  def create_user
    User.create!(
      email: "legacy-migration-#{SecureRandom.hex(4)}@example.com",
      password: "password",
      role: :customer
    )
  end

  def attach_fixture(attachment, fixture, filename, content_type)
    blob = upload_fixture_blob(fixture, filename, content_type)
    attachment.attach(blob)
    blob
  end

  def upload_fixture_blob(fixture, filename, content_type)
    File.open(file_fixture(fixture), "rb") do |io|
      ActiveStorage::Blob.create_and_upload!(io:, filename:, content_type:, identify: false).tap do |blob|
        track_blobs(blob)
      end
    end
  end

  def dimensions(blob)
    blob.open do |file|
      image = MiniMagick::Image.open(file.path)
      [ image.width, image.height ]
    end
  end

  def track_blobs(*blobs)
    @tracked_blob_ids.concat(blobs.map(&:id))
  end
end
