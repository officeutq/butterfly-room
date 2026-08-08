# frozen_string_literal: true

require "test_helper"
require "json"
require "rake"

class ImageAttachmentsInventoryTaskTest < ActiveSupport::TestCase
  TASK_NAME = "image_attachments:inventory"
  INVENTORY_ENV_KEYS = %w[
    IMAGE_INVENTORY_INSPECT_ALL
    IMAGE_INVENTORY_LIMIT
    IMAGE_INVENTORY_AFTER_ATTACHMENT_ID
    IMAGE_INVENTORY_RECORD_TYPE
    IMAGE_INVENTORY_RECORD_ID
  ].freeze

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?(TASK_NAME)
    Rake::Task[TASK_NAME].reenable
    @original_inventory_environment = ENV.to_h.slice(*INVENTORY_ENV_KEYS)
    INVENTORY_ENV_KEYS.each { |key| ENV.delete(key) }
    @store = Store.create!(name: "Inventory Task Store")
    attach_heic(@store.thumbnail)
  end

  teardown do
    INVENTORY_ENV_KEYS.each do |key|
      if @original_inventory_environment.key?(key)
        ENV[key] = @original_inventory_environment.fetch(key)
      else
        ENV.delete(key)
      end
    end
  end

  test "outputs JSON Lines dry-run report without changing attachments" do
    out = nil

    assert_no_difference([ "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ]) do
      out, = capture_io { Rake::Task[TASK_NAME].invoke }
    end

    payloads = out.lines.map { |line| JSON.parse(line) }
    summary = payloads.first
    entry = payloads.second

    assert_equal "image_attachment_inventory_summary", summary.fetch("event")
    assert_equal true, summary.fetch("dry_run")
    assert_equal "metadata_candidates", summary.fetch("selection")
    assert_equal 1, summary.fetch("metadata_candidate_count")
    assert_equal "image_attachment_inventory_entry", entry.fetch("event")
    assert_equal @store.id, entry.fetch("record_id")
    assert_equal "needs_normalization", entry.fetch("status")
  end

  test "supports a bounded inspect all report" do
    ENV["IMAGE_INVENTORY_INSPECT_ALL"] = "true"
    ENV["IMAGE_INVENTORY_LIMIT"] = "10"

    out, = capture_io { Rake::Task[TASK_NAME].invoke }
    summary = JSON.parse(out.lines.first)

    assert_equal "all_target_attachments", summary.fetch("selection")
    assert_equal 10, summary.fetch("limit")
    assert summary.fetch("last_attachment_id").positive?
  end

  test "rejects unbounded inspect all" do
    ENV["IMAGE_INVENTORY_INSPECT_ALL"] = "true"

    _, error = capture_io do
      assert_raises(SystemExit) { Rake::Task[TASK_NAME].invoke }
    end

    assert_includes error, "limit is required when inspect_all is enabled"
  end

  private

  def attach_heic(attachment)
    File.open(file_fixture("sample.heic"), "rb") do |io|
      attachment.attach(
        io:,
        filename: "inventory.heic",
        content_type: "application/octet-stream",
        identify: false
      )
    end
  end
end
