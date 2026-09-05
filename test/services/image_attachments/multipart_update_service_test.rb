# frozen_string_literal: true

require "test_helper"
require "mini_magick"
require "tempfile"

class ImageAttachments::MultipartUpdateServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @record = User.create!(
      email: "multipart-#{SecureRandom.hex(8)}@example.com",
      password: "password",
      role: :customer
    )
    @tempfiles = []
  end

  teardown do
    @record.destroy! if @record.persisted?
    perform_enqueued_jobs
    clear_enqueued_jobs
    clear_performed_jobs
    @tempfiles.each(&:close!)
  end

  test "replace validates and preserves two distinct JPEG byte streams before one pair update" do
    source = jpeg_upload(1200, 1200, color: "red")
    display = jpeg_upload(1024, 1024, color: "blue")

    service(payload: replace_payload(source:, display:), attributes: { bio: "画像と同時更新" }).call

    @record.reload
    assert_not_equal @record.avatar_source.blob.id, @record.avatar.blob.id
    assert_equal File.binread(source.tempfile.path), @record.avatar_source.download
    assert_equal File.binread(display.tempfile.path), @record.avatar.download
    assert_equal @record.avatar_source.blob.id, @record.avatar_crop_data.fetch("sourceBlobId")
    assert_equal "画像と同時更新", @record.bio
    assert_not ImageAttachments::StagedBlobMetadata.owned?(@record.avatar_source.blob)
    assert_not ImageAttachments::StagedBlobMetadata.owned?(@record.avatar.blob)
  end

  test "multiple purposes and normal attributes commit in one transaction" do
    avatar_source = jpeg_upload(1200, 1200, color: "red")
    avatar_display = jpeg_upload(1024, 1024, color: "blue")
    cover_source = jpeg_upload(1200, 630, color: "green")
    cover_display = jpeg_upload(1200, 630, color: "yellow")

    multi_service(
      updates: {
        avatar: replace_payload(source: avatar_source, display: avatar_display),
        cover: social_replace_payload(source: cover_source, display: cover_display)
      },
      attributes: { bio: "2用途と同時更新" }
    ).call

    @record.reload
    assert_equal "2用途と同時更新", @record.bio
    assert_equal File.binread(avatar_source.tempfile.path), @record.avatar_source.download
    assert_equal File.binread(avatar_display.tempfile.path), @record.avatar.download
    assert_equal File.binread(cover_source.tempfile.path), @record.cover_image_source.download
    assert_equal File.binread(cover_display.tempfile.path), @record.cover_image.download
    assert_equal @record.avatar_source.blob.id, @record.avatar_crop_data.fetch("sourceBlobId")
    assert_equal @record.cover_image_source.blob.id, @record.cover_image_crop_data.fetch("sourceBlobId")
  end

  test "a stale second purpose rolls back the first purpose and removes every staged Blob" do
    avatar_expected = snapshot_hash
    cover_expected = snapshot_hash(:cover)
    @record.cover_image.attach(blob)
    competing_cover_id = @record.cover_image.blob.id
    count = ActiveStorage::Blob.count

    assert_raises(ImageAttachments::StagedPairUpdateService::StalePairError) do
      multi_service(
        updates: {
          avatar: replace_payload(
            source: jpeg_upload(1200, 1200),
            display: jpeg_upload(1024, 1024),
            expected: avatar_expected
          ),
          cover: social_replace_payload(
            source: jpeg_upload(1200, 630),
            display: jpeg_upload(1200, 630),
            expected: cover_expected
          )
        },
        attributes: { bio: "保存されない" }
      ).call
    end

    @record.reload
    assert_empty_pair
    assert_equal competing_cover_id, @record.cover_image.blob.id
    assert_nil @record.bio
    assert_equal count, ActiveStorage::Blob.count
  end

  test "reedit uploads only display and preserves the editing source" do
    install_pair
    source_blob = @record.avatar_source.blob
    previous_display_blob = @record.avatar.blob
    edited_display = jpeg_upload(1024, 1024, color: "green")
    edited_crop = crop_data.deep_merge(
      "crop" => { "x" => 100, "y" => 100, "width" => 1000, "height" => 1000 },
      "zoom" => 1.2,
      "sourceBlobId" => 999_999
    )

    perform_enqueued_jobs do
      service(payload: payload(
        operation: "reedit",
        display: edited_display,
        crop_data: edited_crop,
        expected: snapshot_hash
      )).call
    end

    @record.reload
    assert_equal source_blob.id, @record.avatar_source.blob.id
    assert_not_equal previous_display_blob.id, @record.avatar.blob.id
    assert_equal File.binread(edited_display.tempfile.path), @record.avatar.download
    assert_equal source_blob.id, @record.avatar_crop_data.fetch("sourceBlobId")
    assert_equal 1.2, @record.avatar_crop_data.fetch("zoom")
    assert_not ActiveStorage::Blob.exists?(previous_display_blob.id)
  end

  test "delete removes both attachments and crop data without staging blobs" do
    install_pair
    source_blob = @record.avatar_source.blob
    display_blob = @record.avatar.blob

    perform_enqueued_jobs do
      service(payload: payload(operation: "delete", expected: snapshot_hash)).call
    end

    @record.reload
    assert_not @record.avatar_source.attached?
    assert_not @record.avatar.attached?
    assert_equal({}, @record.avatar_crop_data)
    assert_not ActiveStorage::Blob.exists?(source_blob.id)
    assert_not ActiveStorage::Blob.exists?(display_blob.id)
  end

  test "invalid second image is rejected before any Blob is created" do
    invalid_display = jpeg_upload(800, 800)

    assert_no_difference("ActiveStorage::Blob.count") do
      assert_raises(ImageAttachments::PairValidator::Invalid) do
        service(payload: replace_payload(
          source: jpeg_upload(1200, 1200),
          display: invalid_display
        )).call
      end
    end
    assert_empty_pair
  end

  test "second storage failure removes the first staged Blob and keeps the old state" do
    real_uploader = ImageAttachments::StagedBlobUploadService
    failing_uploader = Class.new do
      define_method(:initialize) { |**arguments| @arguments = arguments }
      define_method(:call) do
        if @arguments.fetch(:role) == :display
          raise ImageAttachments::StagedBlobUploadService::UploadFailedError, "simulated"
        end

        real_uploader.new(**@arguments).call
      end
    end

    assert_no_difference("ActiveStorage::Blob.count") do
      assert_raises(ImageAttachments::StagedBlobUploadService::UploadFailedError) do
        service(
          payload: replace_payload(
            source: jpeg_upload(1200, 1200),
            display: jpeg_upload(1024, 1024)
          ),
          blob_upload_service: failing_uploader
        ).call
      end
    end
    assert_empty_pair
  end

  test "a duplicate request with the same expected IDs cannot overwrite the first result" do
    expected = snapshot_hash
    first_source = jpeg_upload(1200, 1200, color: "red")
    first_display = jpeg_upload(1024, 1024, color: "blue")
    service(payload: replace_payload(source: first_source, display: first_display, expected:)).call
    @record.reload
    committed_source_id = @record.avatar_source.blob.id
    committed_display_id = @record.avatar.blob.id
    committed_blob_count = ActiveStorage::Blob.count

    assert_raises(ImageAttachments::StagedPairUpdateService::StalePairError) do
      service(payload: replace_payload(
        source: jpeg_upload(1200, 1200, color: "green"),
        display: jpeg_upload(1024, 1024, color: "yellow"),
        expected:
      )).call
    end

    @record.reload
    assert_equal committed_source_id, @record.avatar_source.blob.id
    assert_equal committed_display_id, @record.avatar.blob.id
    assert_equal committed_blob_count, ActiveStorage::Blob.count
  end

  test "checks existence through the configured Active Storage service boundary" do
    upload = jpeg_upload(1200, 1200)
    storage = ActiveStorage::Blob.service
    checked_key = nil

    with_stubbed_method(storage, :exist?, ->(key) { checked_key = key; true }) do
      blob = ImageAttachments::StagedBlobUploadService.new(
        record: @record,
        purpose: :avatar,
        role: :source,
        upload:
      ).call

      assert_equal blob.key, checked_key
      assert_equal storage.name.to_s, blob.service_name
      assert ImageAttachments::StagedBlobMetadata.owned?(blob, purpose: :avatar, role: :source)
      ImageAttachments::StagedBlobPurgeService.new(blob:).call
    end
  end

  test "missing storage object is retryable and leaves no staged Blob row" do
    upload = jpeg_upload(1200, 1200)
    storage = ActiveStorage::Blob.service

    assert_no_difference("ActiveStorage::Blob.count") do
      with_stubbed_method(storage, :exist?, ->(_key) { false }) do
        error = assert_raises(ImageAttachments::StagedBlobUploadService::UploadFailedError) do
          ImageAttachments::StagedBlobUploadService.new(
            record: @record,
            purpose: :avatar,
            role: :source,
            upload:
          ).call
        end
        assert_match(/保存先/, error.message)
      end
    end
  end

  private

  def service(payload:, attributes: {}, blob_upload_service: ImageAttachments::StagedBlobUploadService)
    ImageAttachments::MultipartUpdateService.new(
      record: @record,
      purpose: :avatar,
      payload:,
      attributes:,
      blob_upload_service:
    )
  end

  def multi_service(updates:, attributes: {})
    ImageAttachments::MultipartUpdateService.new(
      record: @record,
      updates:,
      attributes:
    )
  end

  def install_pair
    service(payload: replace_payload(
      source: jpeg_upload(1200, 1200, color: "gray"),
      display: jpeg_upload(1024, 1024, color: "black")
    )).call
    @record.reload
  end

  def replace_payload(source:, display:, expected: snapshot_hash)
    payload(
      operation: "replace",
      source:,
      display:,
      crop_data: crop_data,
      expected:
    )
  end

  def social_replace_payload(source:, display:, expected: snapshot_hash(:cover))
    payload(
      operation: "replace",
      source:,
      display:,
      crop_data: social_crop_data,
      expected:
    )
  end

  def payload(operation:, expected:, source: nil, display: nil, crop_data: nil)
    {
      operation:,
      source:,
      display:,
      crop_data: crop_data && JSON.generate(crop_data),
      expected:
    }
  end

  def snapshot_hash(purpose = :avatar)
    snapshot = ImageAttachments::StagedPairUpdateService.capture(record: @record, purpose:)
    snapshot.to_h
  end

  def crop_data
    {
      "schemaVersion" => 1,
      "ratioKey" => "square",
      "source" => { "width" => 1200, "height" => 1200 },
      "crop" => { "x" => 0, "y" => 0, "width" => 1200, "height" => 1200 },
      "zoom" => 1.0,
      "output" => {
        "width" => 1024,
        "height" => 1024,
        "mimeType" => "image/jpeg",
        "quality" => 0.9
      }
    }
  end

  def social_crop_data
    {
      "schemaVersion" => 1,
      "ratioKey" => "social",
      "source" => { "width" => 1200, "height" => 630 },
      "crop" => { "x" => 0, "y" => 0, "width" => 1200, "height" => 630 },
      "zoom" => 1.0,
      "output" => {
        "width" => 1200,
        "height" => 630,
        "mimeType" => "image/jpeg",
        "quality" => 0.9
      }
    }
  end

  def blob
    File.open(file_fixture("sample.jpg"), "rb") do |io|
      ActiveStorage::Blob.create_and_upload!(
        io:,
        filename: "existing.jpg",
        content_type: "image/jpeg",
        identify: false
      )
    end
  end

  def jpeg_upload(width, height, color: "purple")
    file = Tempfile.new([ "multipart-image", ".jpg" ]).tap { |tempfile| @tempfiles << tempfile }
    MiniMagick.convert do |command|
      command.size("#{width}x#{height}")
      command << "xc:#{color}"
      command << "JPEG:#{file.path}"
    end
    file.binmode
    file.rewind
    ActionDispatch::Http::UploadedFile.new(
      tempfile: file,
      filename: "client-name.jpg",
      type: "image/jpeg"
    )
  end

  def assert_empty_pair
    @record.reload
    assert_not @record.avatar_source.attached?
    assert_not @record.avatar.attached?
    assert_equal({}, @record.avatar_crop_data)
  end

  def with_stubbed_method(object, name, replacement)
    singleton_class = object.singleton_class
    original = object.method(name)
    singleton_class.define_method(name) do |*args, **kwargs, &block|
      replacement.call(*args, **kwargs, &block)
    end
    yield
  ensure
    singleton_class.define_method(name, original)
  end
end
