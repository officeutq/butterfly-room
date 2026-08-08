# frozen_string_literal: true

require "test_helper"

class ImageAttachments::UpdateServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @store = Store.create!(name: "画像更新前店舗")
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "normalizes an uploaded image before updating attributes and attachment" do
    result = update_service(
      attributes: { name: "画像更新後店舗" },
      upload: uploaded_file("sample.heic", "image/png")
    ).call

    assert_equal @store, result

    @store.reload
    assert_equal "画像更新後店舗", @store.name
    assert @store.thumbnail.attached?
    assert_equal "sample.jpg", @store.thumbnail.filename.to_s
    assert_equal "image/jpeg", @store.thumbnail.content_type
    assert_equal "\xFF\xD8".b, @store.thumbnail.download.first(2)
    assert @store.thumbnail.blob.service.exist?(@store.thumbnail.key)
  end

  test "replaces an existing attachment and purges its old blob after commit" do
    old_blob = attach_existing_thumbnail

    perform_enqueued_jobs do
      update_service(upload: uploaded_file("sample.png", "image/png")).call
    end

    @store.reload
    assert @store.thumbnail.attached?
    assert_not_equal old_blob.id, @store.thumbnail.blob.id
    assert_not ActiveStorage::Blob.exists?(old_blob.id)
  end

  test "removes an existing attachment when no new upload is present" do
    old_blob = attach_existing_thumbnail

    perform_enqueued_jobs do
      update_service(remove_attachment: true).call
    end

    @store.reload
    assert_not @store.thumbnail.attached?
    assert_not ActiveStorage::Blob.exists?(old_blob.id)
  end

  test "prioritizes a new upload over the removal flag" do
    old_blob = attach_existing_thumbnail

    perform_enqueued_jobs do
      update_service(
        upload: uploaded_file("sample.webp", "image/webp"),
        remove_attachment: true
      ).call
    end

    @store.reload
    assert @store.thumbnail.attached?
    assert_equal "sample.jpg", @store.thumbnail.filename.to_s
    assert_not_equal old_blob.id, @store.thumbnail.blob.id
    assert_not ActiveStorage::Blob.exists?(old_blob.id)
  end

  test "updates attributes without replacing or checking an unchanged attachment" do
    old_blob = attach_existing_thumbnail
    updater = update_service(attributes: { name: "画像未変更店舗" })
    updater.define_singleton_method(:upload_normalized_blob) do
      flunk "an unchanged attachment must not be uploaded"
    end
    updater.define_singleton_method(:blob_uploaded?) do |_blob|
      flunk "an unchanged attachment must not be checked in storage"
    end

    assert_no_difference("ActiveStorage::Blob.count") { updater.call }

    @store.reload
    assert_equal "画像未変更店舗", @store.name
    assert_equal old_blob.id, @store.thumbnail.blob.id
  end

  test "keeps existing attributes and attachment when image conversion fails" do
    old_blob = attach_existing_thumbnail

    assert_no_difference("ActiveStorage::Blob.count") do
      assert_raises(ImageAttachments::UpdateService::ImageProcessingError) do
        update_service(
          attributes: { name: "保存されない店舗名" },
          upload: uploaded_file("corrupt.heic", "image/heic")
        ).call
      end
    end

    @store.reload
    assert_equal "画像更新前店舗", @store.name
    assert_equal old_blob.id, @store.thumbnail.blob.id
  end

  test "purges the new blob and keeps existing state when upload verification fails" do
    old_blob = attach_existing_thumbnail
    updater = update_service(
      attributes: { name: "保存されない店舗名" },
      upload: uploaded_file("sample.heic", "image/heic")
    )
    updater.define_singleton_method(:blob_uploaded?) { |_blob| false }

    assert_no_difference("ActiveStorage::Blob.count") do
      assert_raises(ImageAttachments::UpdateService::UploadFailedError) { updater.call }
    end

    @store.reload
    assert_equal "画像更新前店舗", @store.name
    assert_equal old_blob.id, @store.thumbnail.blob.id
  end

  test "purges the new blob and rolls back attributes when record validation fails" do
    old_blob = attach_existing_thumbnail

    assert_no_difference("ActiveStorage::Blob.count") do
      assert_raises(ActiveRecord::RecordInvalid) do
        update_service(
          attributes: { name: "" },
          upload: uploaded_file("sample.heic", "image/heic")
        ).call
      end
    end

    @store.reload
    assert_equal "画像更新前店舗", @store.name
    assert_equal old_blob.id, @store.thumbnail.blob.id
  end

  test "rolls back the attachment attributes and yielded database work together" do
    booth = Booth.create!(store: @store, name: "更新前ブース")
    old_blob = attach_existing_image(booth.thumbnail_image, filename: "old-booth.jpg")
    cast = User.create!(email: "image-update-cast@example.com", password: "password", role: :cast)
    updater = described_service.new(
      record: booth,
      attachment_name: :thumbnail_image,
      attributes: { name: "保存されないブース名" },
      upload: uploaded_file("sample.heic", "image/heic"),
      remove_attachment: false,
      max_width: 24,
      max_height: 24
    )

    assert_no_difference([ "ActiveStorage::Blob.count", "BoothCast.count" ]) do
      assert_raises(ActiveRecord::RecordInvalid) do
        updater.call do |updated_booth|
          BoothCast.create!(booth: updated_booth, cast_user: cast)
          updated_booth.errors.add(:base, "transaction failure")
          raise ActiveRecord::RecordInvalid, updated_booth
        end
      end
    end

    booth.reload
    assert_equal "更新前ブース", booth.name
    assert_equal old_blob.id, booth.thumbnail_image.blob.id
  end

  private

  def described_service
    ImageAttachments::UpdateService
  end

  def update_service(attributes: {}, upload: nil, remove_attachment: false)
    described_service.new(
      record: @store,
      attachment_name: :thumbnail,
      attributes:,
      upload:,
      remove_attachment:,
      max_width: 24,
      max_height: 24
    )
  end

  def uploaded_file(filename, content_type)
    Rack::Test::UploadedFile.new(file_fixture(filename), content_type, true)
  end

  def attach_existing_thumbnail
    attach_existing_image(@store.thumbnail, filename: "old-store.jpg")
  end

  def attach_existing_image(attachment, filename:)
    File.open(file_fixture("sample.jpg"), "rb") do |io|
      attachment.attach(io:, filename:, content_type: "image/jpeg", identify: false)
    end

    attachment.blob
  end
end
