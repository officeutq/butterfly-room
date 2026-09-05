# frozen_string_literal: true

require "test_helper"
require "json"
require "rake"

class ImageAttachmentsLegacyMigrationTaskTest < ActiveSupport::TestCase
  TASK_NAME = "image_attachments:migrate_legacy_pairs"
  MIGRATION_ENV_KEYS = %w[
    IMAGE_MIGRATION_APPLY
    IMAGE_MIGRATION_CONFIRM
    IMAGE_MIGRATION_RECORD_TYPE
    IMAGE_MIGRATION_RECORD_ID
    IMAGE_MIGRATION_MIN_ATTACHMENT_ID
    IMAGE_MIGRATION_MAX_ATTACHMENT_ID
    IMAGE_MIGRATION_AFTER_ATTACHMENT_ID
    IMAGE_MIGRATION_LIMIT
    IMAGE_MIGRATION_EXPECTED_ATTACHMENT_ID
    IMAGE_MIGRATION_EXPECTED_BLOB_ID
    IMAGE_MIGRATION_GIT_COMMIT
  ].freeze

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?(TASK_NAME)
    Rake::Task[TASK_NAME].reenable
    @original_environment = ENV.to_h.slice(*MIGRATION_ENV_KEYS)
    MIGRATION_ENV_KEYS.each { |key| ENV.delete(key) }

    @store = Store.create!(name: "Legacy Migration Task Store")
    File.open(file_fixture("sample.png"), "rb") do |io|
      @store.thumbnail.attach(
        io:,
        filename: "private-store-name.png",
        content_type: "image/png",
        identify: false
      )
    end
    @legacy_attachment_id = @store.thumbnail.attachment.id
    @legacy_blob_id = @store.thumbnail.blob.id
    set_record_scope
  end

  teardown do
    MIGRATION_ENV_KEYS.each do |key|
      if @original_environment.key?(key)
        ENV[key] = @original_environment.fetch(key)
      else
        ENV.delete(key)
      end
    end
  end

  test "defaults to JSON Lines dry run without exposing filenames or storage keys" do
    out = nil
    assert_no_difference([ "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ]) do
      out, = capture_io { Rake::Task[TASK_NAME].invoke }
    end

    payloads = out.lines.map { |line| JSON.parse(line) }
    summary, entry = payloads
    assert_equal "legacy_image_pair_migration_summary", summary.fetch("event")
    assert_equal true, summary.fetch("dry_run")
    assert_equal 1, summary.fetch("selected_count")
    assert_equal({ "eligible" => 1 }, summary.fetch("status_counts"))
    assert_equal "legacy_image_pair_migration_entry", entry.fetch("event")
    assert_equal "thumbnail", entry.fetch("purpose")
    assert_equal @legacy_attachment_id, entry.fetch("legacy_attachment_id")
    assert_equal @legacy_blob_id, entry.fetch("legacy_blob_id")
    assert_not_includes out, "private-store-name"
    assert_not_includes out, @store.thumbnail.blob.key
    assert_not_includes entry.keys, "filename"
  end

  test "rejects apply without bounded options, commit and exact confirmation" do
    ENV["IMAGE_MIGRATION_APPLY"] = "true"
    ENV["IMAGE_MIGRATION_GIT_COMMIT"] = "9e25806"

    out, error = capture_io do
      assert_raises(SystemExit) { Rake::Task[TASK_NAME].invoke }
    end

    payload = JSON.parse(out)
    assert_equal "legacy_image_pair_migration_failure", payload.fetch("event")
    assert_equal false, payload.fetch("dry_run")
    assert_equal "ArgumentError", payload.fetch("error_class")
    assert_includes error, "limit is required"
    assert_equal @legacy_blob_id, @store.reload.thumbnail.blob.id
  end

  test "applies one explicitly confirmed record and records the execution commit" do
    ENV["IMAGE_MIGRATION_APPLY"] = "true"
    ENV["IMAGE_MIGRATION_CONFIRM"] = ImageAttachments::LegacyMigrationService::APPLY_CONFIRMATION
    ENV["IMAGE_MIGRATION_LIMIT"] = "1"
    ENV["IMAGE_MIGRATION_GIT_COMMIT"] = "9e25806"

    out, = capture_io { Rake::Task[TASK_NAME].invoke }

    summary, entry = out.lines.map { |line| JSON.parse(line) }
    assert_equal false, summary.fetch("dry_run")
    assert_equal "9e25806", summary.fetch("git_commit")
    assert_equal({ "migrated" => 1 }, summary.fetch("status_counts"))
    assert_equal "migrated", entry.fetch("status")
    assert @store.reload.thumbnail_source.attached?
    assert_not_equal @legacy_blob_id, @store.thumbnail.blob.id
    assert_equal @store.thumbnail_source.blob.id, @store.thumbnail_crop_data.fetch("sourceBlobId")
  end

  test "validates lowercase git commit metadata" do
    ENV["IMAGE_MIGRATION_GIT_COMMIT"] = "NOT-A-SHA"

    out, error = capture_io do
      assert_raises(SystemExit) { Rake::Task[TASK_NAME].invoke }
    end

    assert_equal "ArgumentError", JSON.parse(out).fetch("error_class")
    assert_includes error, "7-40 character lowercase Git SHA"
  end

  private

  def set_record_scope
    ENV["IMAGE_MIGRATION_RECORD_TYPE"] = "Store"
    ENV["IMAGE_MIGRATION_RECORD_ID"] = @store.id.to_s
    ENV["IMAGE_MIGRATION_EXPECTED_ATTACHMENT_ID"] = @legacy_attachment_id.to_s
    ENV["IMAGE_MIGRATION_EXPECTED_BLOB_ID"] = @legacy_blob_id.to_s
  end
end
