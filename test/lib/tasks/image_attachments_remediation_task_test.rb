# frozen_string_literal: true

require "test_helper"
require "json"
require "rake"

class ImageAttachmentsRemediationTaskTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  TASK_NAME = "image_attachments:remediate"
  REMEDIATION_ENV_KEYS = %w[
    IMAGE_REMEDIATION_RECORD_TYPE
    IMAGE_REMEDIATION_RECORD_ID
    IMAGE_REMEDIATION_ATTACHMENT_NAME
    IMAGE_REMEDIATION_EXPECTED_ATTACHMENT_ID
    IMAGE_REMEDIATION_EXPECTED_BLOB_ID
    IMAGE_REMEDIATION_APPLY
    IMAGE_REMEDIATION_CONFIRM
  ].freeze

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?(TASK_NAME)
    Rake::Task[TASK_NAME].reenable
    @original_environment = ENV.to_h.slice(*REMEDIATION_ENV_KEYS)
    REMEDIATION_ENV_KEYS.each { |key| ENV.delete(key) }

    @store = Store.create!(name: "Remediation Task Store")
    @old_blob = attach_heic(@store.thumbnail)
    @old_attachment_id = @store.thumbnail.attachment.id
    set_target_environment
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    REMEDIATION_ENV_KEYS.each do |key|
      if @original_environment.key?(key)
        ENV[key] = @original_environment.fetch(key)
      else
        ENV.delete(key)
      end
    end
  end

  test "defaults to a read-only eligible result" do
    out = nil

    assert_no_difference([ "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ]) do
      out, = capture_io { Rake::Task[TASK_NAME].invoke }
    end

    payload = JSON.parse(out)
    assert_equal "image_attachment_remediation_result", payload.fetch("event")
    assert_equal true, payload.fetch("dry_run")
    assert_equal "eligible", payload.fetch("status")
    assert_equal @old_attachment_id, payload.fetch("attachment_id")
    assert_equal @old_blob.id, @store.reload.thumbnail.blob.id
  end

  test "rejects apply without the exact confirmation value" do
    ENV["IMAGE_REMEDIATION_APPLY"] = "true"

    out, error = capture_io do
      assert_raises(SystemExit) { Rake::Task[TASK_NAME].invoke }
    end

    payload = JSON.parse(out)
    assert_equal false, payload.fetch("dry_run")
    assert_equal "failed", payload.fetch("status")
    assert_equal "ArgumentError", payload.fetch("error_class")
    assert_includes error, "IMAGE_REMEDIATION_CONFIRM"
    assert_equal @old_blob.id, @store.reload.thumbnail.blob.id
  end

  test "applies one confirmed target" do
    ENV["IMAGE_REMEDIATION_APPLY"] = "true"
    ENV["IMAGE_REMEDIATION_CONFIRM"] = confirmation_value

    out = nil
    perform_enqueued_jobs do
      out, = capture_io { Rake::Task[TASK_NAME].invoke }
    end

    payload = JSON.parse(out)
    assert_equal false, payload.fetch("dry_run")
    assert_equal "normalized", payload.fetch("status")
    assert_equal "image/jpeg", payload.fetch("content_type")
    assert_equal "JPEG", payload.fetch("actual_format")
    assert_not_equal @old_blob.id, @store.reload.thumbnail.blob.id
    assert_not ActiveStorage::Blob.exists?(@old_blob.id)
  end

  private

  def set_target_environment
    ENV["IMAGE_REMEDIATION_RECORD_TYPE"] = "Store"
    ENV["IMAGE_REMEDIATION_RECORD_ID"] = @store.id.to_s
    ENV["IMAGE_REMEDIATION_ATTACHMENT_NAME"] = "thumbnail"
    ENV["IMAGE_REMEDIATION_EXPECTED_ATTACHMENT_ID"] = @old_attachment_id.to_s
    ENV["IMAGE_REMEDIATION_EXPECTED_BLOB_ID"] = @old_blob.id.to_s
  end

  def confirmation_value
    [ "Store", @store.id, "thumbnail", @old_attachment_id, @old_blob.id ].join(":")
  end

  def attach_heic(attachment)
    File.open(file_fixture("sample.heic"), "rb") do |io|
      attachment.attach(
        io:,
        filename: "remediation.heic",
        content_type: "image/heic",
        identify: false
      )
    end
    attachment.blob
  end
end
