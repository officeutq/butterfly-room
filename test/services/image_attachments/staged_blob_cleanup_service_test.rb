# frozen_string_literal: true

require "test_helper"
require "yaml"

class ImageAttachments::StagedBlobCleanupServiceTest < ActiveSupport::TestCase
  setup do
    @blob_ids = []
    @records = []
    @purpose = User.image_attachment_purpose_for(:avatar)
  end

  teardown do
    @records.each { |record| record.destroy! if record.persisted? }
    @blob_ids.each do |id|
      stored_blob = ActiveStorage::Blob.find_by(id:)
      stored_blob&.purge unless stored_blob&.attachments&.exists?
    end
  end

  test "metadata marks purpose role and cleanup time without discarding existing metadata" do
    stored_blob = blob
    stored_blob.update!(metadata: { "identified" => true, "custom" => "kept" })
    cleanup_after = 30.minutes.from_now

    described_metadata.mark!(stored_blob, purpose: @purpose, role: :source, cleanup_after:)

    stored_blob.reload
    assert described_metadata.owned?(stored_blob, purpose: @purpose, role: :source)
    assert described_metadata.active?(stored_blob, purpose: @purpose, role: :source, at: Time.current)
    assert_equal "kept", stored_blob.metadata.fetch("custom")

    described_metadata.clear!(stored_blob)
    assert_not described_metadata.owned?(stored_blob.reload)
    assert_equal "kept", stored_blob.metadata.fetch("custom")
  end

  test "cleanup purges only expired owned and unattached blobs" do
    future = staged_blob(:source, cleanup_after: 1.hour.from_now)
    expired = staged_blob(:display, cleanup_after: 1.hour.ago)
    attached = staged_blob(:display, cleanup_after: 1.hour.ago)
    unrelated = blob
    user = create_user
    user.avatar.attach(attached)
    relation = ActiveStorage::Blob.where(id: [ future.id, expired.id, attached.id, unrelated.id ])

    result = described_class.new(relation:, now: Time.current).call

    assert_equal 3, result.inspected
    assert_equal 1, result.purged
    assert_equal 2, result.skipped
    assert ActiveStorage::Blob.exists?(future.id)
    assert_not ActiveStorage::Blob.exists?(expired.id)
    assert ActiveStorage::Blob.exists?(attached.id)
    assert ActiveStorage::Blob.exists?(unrelated.id)
    assert attached.service.exist?(attached.key)
  end

  test "cleanup keeps malformed staging metadata" do
    malformed = blob
    malformed.update!(
      metadata: {
        described_metadata::MARKER_KEY => {
          "schemaVersion" => 1,
          "purpose" => "avatar",
          "role" => "display",
          "cleanupAfter" => "not-a-time"
        }
      }
    )

    result = described_class.new(
      relation: ActiveStorage::Blob.where(id: malformed.id),
      now: Time.current
    ).call

    assert_equal 1, result.inspected
    assert_equal 0, result.purged
    assert_equal 1, result.skipped
    assert ActiveStorage::Blob.exists?(malformed.id)
  end

  test "storage failure keeps blob row and metadata for a later retry" do
    expired = staged_blob(:display, cleanup_after: 1.hour.ago)
    failing_purger = Class.new do
      def initialize(blob:)
        @blob = blob
      end

      def call
        raise IOError, "controlled storage failure for #{@blob.id}"
      end
    end

    assert_raises(described_class::CleanupError) do
      described_class.new(
        relation: ActiveStorage::Blob.where(id: expired.id),
        now: Time.current,
        purger: failing_purger
      ).call
    end

    assert ActiveStorage::Blob.exists?(expired.id)
    assert described_metadata.owned?(expired.reload)
    assert expired.service.exist?(expired.key)
  end

  test "purge service refuses unrelated and attached blobs" do
    unrelated = blob
    attached = staged_blob(:source, cleanup_after: 1.hour.ago)
    user = create_user
    user.avatar_source.attach(attached)

    assert_raises(ImageAttachments::StagedBlobPurgeService::RefusedError) do
      ImageAttachments::StagedBlobPurgeService.new(blob: unrelated).call
    end
    assert_not ImageAttachments::StagedBlobPurgeService.new(blob: attached).call
    assert ActiveStorage::Blob.exists?(unrelated.id)
    assert ActiveStorage::Blob.exists?(attached.id)
  end

  test "cleanup job exposes cleanup failures to the job adapter" do
    failure = ImageAttachments::StagedBlobCleanupService::CleanupError.new("controlled failure")
    fake_service = Object.new
    fake_service.define_singleton_method(:call) { raise failure }
    job = ImageAttachments::StagedBlobCleanupJob.new
    job.define_singleton_method(:cleanup_service) { fake_service }

    assert_raises(ImageAttachments::StagedBlobCleanupService::CleanupError) do
      job.perform
    end
  end

  test "production recurring config runs staged blob cleanup every five minutes" do
    config = YAML.safe_load_file(Rails.root.join("config/recurring.yml"))
    task = config.fetch("production").fetch("image_attachment_staged_blob_cleanup")

    assert_equal "ImageAttachments::StagedBlobCleanupJob", task.fetch("class")
    assert_equal "default", task.fetch("queue")
    assert_equal "every 5 minutes", task.fetch("schedule")
  end

  private

  def described_class
    ImageAttachments::StagedBlobCleanupService
  end

  def described_metadata
    ImageAttachments::StagedBlobMetadata
  end

  def create_user
    record = User.create!(
      email: "staged-cleanup-#{SecureRandom.hex(8)}@example.com",
      password: "password",
      role: :customer
    )
    @records << record
    record
  end

  def staged_blob(role, cleanup_after:)
    blob.tap do |stored_blob|
      described_metadata.mark!(stored_blob, purpose: @purpose, role:, cleanup_after:)
    end
  end

  def blob
    File.open(file_fixture("sample.jpg"), "rb") do |io|
      stored_blob = ActiveStorage::Blob.create_and_upload!(
        io:,
        filename: "staged-cleanup.jpg",
        content_type: "image/jpeg",
        identify: false
      )
      @blob_ids << stored_blob.id
      stored_blob
    end
  end
end
