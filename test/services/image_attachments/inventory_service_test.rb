# frozen_string_literal: true

require "test_helper"

class ImageAttachments::InventoryServiceTest < ActiveSupport::TestCase
  test "inspects only metadata candidates from supported display attachments by default" do
    store = Store.create!(name: "Inventory Store")
    heic_blob = attach(
      store.thumbnail,
      fixture: "sample.heic",
      filename: "unavailable.heic",
      content_type: "application/octet-stream"
    )
    user = create_user
    attach(user.avatar, fixture: "sample.jpg", filename: "avatar.jpg", content_type: "image/jpeg")
    drink_item = DrinkItem.create!(store:, name: "Inventory Drink", price_points: 1, position: 0)
    attach(
      drink_item.custom_icon,
      fixture: "sample.heic",
      filename: "drink.heic",
      content_type: "image/heic"
    )

    result = nil
    assert_no_difference([ "ActiveStorage::Blob.count", "ActiveStorage::Attachment.count" ]) do
      result = described_service.new.call
    end

    assert_equal "metadata_candidates", result.selection
    assert_equal 2, result.target_count
    assert_equal 1, result.metadata_candidate_count
    assert_equal 1, result.inspected_count

    entry = result.entries.first
    assert_equal heic_blob.id, entry.blob_id
    assert_equal "Store", entry.record_type
    assert_equal store.id, entry.record_id
    assert_equal "thumbnail", entry.attachment_name
    assert entry.metadata_candidate
    assert entry.stored
    assert_equal "HEIC", entry.actual_format
    assert entry.convertible
    assert_equal "needs_normalization", entry.status
    assert_nil entry.error_class
  end

  test "inspect all requires a limit and reports canonical JPEG attachments" do
    user = create_user
    jpeg_blob = attach(
      user.avatar,
      fixture: "sample.jpg",
      filename: "avatar.jpg",
      content_type: "image/jpeg"
    )

    error = assert_raises(ArgumentError) do
      described_service.new(inspect_all: true)
    end
    assert_equal "limit is required when inspect_all is enabled", error.message

    result = described_service.new(inspect_all: true, limit: 10).call
    entry = result.entries.find { |candidate| candidate.blob_id == jpeg_blob.id }

    assert_equal "all_target_attachments", result.selection
    assert_not entry.metadata_candidate
    assert_equal "JPEG", entry.actual_format
    assert entry.convertible
    assert_equal "ok", entry.status
  end

  test "continues a bounded inspection after the previous attachment id" do
    first_user = create_user
    first_blob = attach(
      first_user.avatar,
      fixture: "sample.jpg",
      filename: "first.jpg",
      content_type: "image/jpeg"
    )
    second_user = create_user
    second_blob = attach(
      second_user.avatar,
      fixture: "sample.jpg",
      filename: "second.jpg",
      content_type: "image/jpeg"
    )

    first_result = described_service.new(inspect_all: true, limit: 1).call
    second_result = described_service.new(
      inspect_all: true,
      limit: 1,
      after_attachment_id: first_result.last_attachment_id
    ).call

    assert_equal first_blob.id, first_result.entries.first.blob_id
    assert_equal first_result.last_attachment_id, second_result.after_attachment_id
    assert_equal second_blob.id, second_result.entries.first.blob_id
    assert_operator second_result.last_attachment_id, :>, first_result.last_attachment_id
  end

  test "reports JPEG bytes with HEIC metadata as a metadata mismatch" do
    store = Store.create!(name: "Metadata Mismatch Store")
    blob = attach(
      store.thumbnail,
      fixture: "sample.jpg",
      filename: "thumbnail.heic",
      content_type: "image/heic"
    )

    entry = described_service.new(
      record_type: "Store",
      record_id: store.id
    ).call.entries.first

    assert_equal blob.id, entry.blob_id
    assert_equal "JPEG", entry.actual_format
    assert entry.convertible
    assert_equal "metadata_mismatch", entry.status
  end

  test "reports missing and corrupt objects without stopping other candidates" do
    missing_store = Store.create!(name: "Missing Inventory Store")
    missing_blob = attach(
      missing_store.thumbnail,
      fixture: "sample.heic",
      filename: "missing.heic",
      content_type: "image/heic"
    )
    missing_blob.service.delete(missing_blob.key)

    corrupt_store = Store.create!(name: "Corrupt Inventory Store")
    corrupt_blob = attach(
      corrupt_store.thumbnail,
      fixture: "corrupt.heic",
      filename: "corrupt.heic",
      content_type: "image/heic"
    )

    result = described_service.new.call
    entries = result.entries.index_by(&:blob_id)

    assert_equal "missing", entries.fetch(missing_blob.id).status
    assert_equal false, entries.fetch(missing_blob.id).stored
    assert_equal "unreadable", entries.fetch(corrupt_blob.id).status
    assert_equal false, entries.fetch(corrupt_blob.id).convertible
  end

  test "validates record filters" do
    assert_raises(ArgumentError) { described_service.new(record_type: "DrinkItem") }
    assert_raises(ArgumentError) { described_service.new(record_id: 1) }
    assert_raises(ArgumentError) { described_service.new(limit: 0) }
    assert_raises(ArgumentError) { described_service.new(after_attachment_id: 0) }
  end

  private

  def described_service
    ImageAttachments::InventoryService
  end

  def create_user
    User.create!(
      email: "inventory-#{SecureRandom.hex(4)}@example.com",
      password: "password",
      role: :customer
    )
  end

  def attach(attachment, fixture:, filename:, content_type:)
    File.open(file_fixture(fixture), "rb") do |io|
      attachment.attach(io:, filename:, content_type:, identify: false)
    end
    attachment.blob
  end
end
