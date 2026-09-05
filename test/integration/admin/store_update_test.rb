# frozen_string_literal: true

require "test_helper"
require "mini_magick"
require "tempfile"

class Admin::StoreUpdateTest < ActionDispatch::IntegrationTest
  include ActionDispatch::TestProcess
  include ActiveJob::TestHelper

  setup do
    @tempfiles = []
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    @tempfiles.each(&:close!)
  end

  test "admin store update redirects to dashboard with notice" do
    admin = User.create!(
      email: "admin_store_update@example.com",
      password: "password",
      password_confirmation: "password",
      role: :store_admin
    )

    store = Store.create!(
      name: "更新前店舗名",
      description: "更新前概要"
    )

    StoreMembership.create!(
      store:,
      user: admin,
      membership_role: :admin
    )

    sign_in admin, scope: :user

    patch admin_store_path(store), params: {
      store: {
        name: "更新後店舗名",
        description: "更新後概要",
        area: "渋谷",
        business_type: store.business_type
      }
    }

    assert_redirected_to dashboard_path
    follow_redirect!
    assert_response :success
    assert_includes @response.body, "店舗情報を更新しました"

    store.reload
    assert_equal "更新後店舗名", store.name
    assert_equal "更新後概要", store.description
    assert_equal "渋谷", store.area
  end

  test "admin store update failure redirects to edit for html request" do
    admin = User.create!(
      email: "admin_store_update_failure@example.com",
      password: "password",
      password_confirmation: "password",
      role: :store_admin
    )

    store = Store.create!(
      name: "更新前店舗名",
      description: "初期概要"
    )

    StoreMembership.create!(
      store:,
      user: admin,
      membership_role: :admin
    )

    sign_in admin, scope: :user

    patch admin_store_path(store), params: {
      store: {
        name: "",
        description: "更新後概要"
      }
    }

    assert_redirected_to edit_admin_store_path(store)

    follow_redirect!
    assert_response :success
    assert_includes @response.body, "店舗設定"

    store.reload
    assert_equal "更新前店舗名", store.name
    assert_equal "初期概要", store.description
  end

  test "admin store update failure returns unprocessable_entity for turbo_stream request" do
    admin = User.create!(
      email: "admin_store_update_failure_turbo@example.com",
      password: "password",
      password_confirmation: "password",
      role: :store_admin
    )

    store = Store.create!(
      name: "更新前店舗名",
      description: "初期概要"
    )

    StoreMembership.create!(
      store:,
      user: admin,
      membership_role: :admin
    )

    sign_in admin, scope: :user

    patch admin_store_path(store),
          params: {
            store: {
              name: "",
              description: "更新後概要"
            }
          },
          as: :turbo_stream

    assert_response :unprocessable_entity
    assert_includes @response.body, "turbo-stream"
    assert_includes @response.body, "flash_inner"

    store.reload
    assert_equal "更新前店舗名", store.name
    assert_equal "初期概要", store.description
  end

  test "store update creates an image pair with normal attributes and returns JSON" do
    admin, store = create_store_admin_and_store("store_image_pair_create")
    sign_in admin, scope: :user

    patch admin_store_path(store),
          params: {
            store: { name: "画像組店舗", description: "画像と一体更新" },
            image_pair: replace_pair_params(store)
          },
          headers: { "ACCEPT" => "application/json" }

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "complete", response_body.fetch("state")
    assert_equal dashboard_path, response_body.fetch("redirect_url")
    store.reload
    assert_equal "画像組店舗", store.name
    assert_equal "画像と一体更新", store.description
    assert_complete_pair(store)
  end

  test "store image pair can be re-edited replaced and deleted" do
    admin, store = create_store_admin_and_store("store_image_pair_operations")
    install_pair(store)
    store.reload
    original_source_id = store.thumbnail_source.blob.id
    original_display_id = store.thumbnail.blob.id
    sign_in admin, scope: :user

    patch admin_store_path(store), params: {
      store: { description: "再編集" },
      image_pair: reedit_pair_params(store)
    }

    assert_redirected_to dashboard_path
    store.reload
    assert_equal "再編集", store.description
    assert_equal original_source_id, store.thumbnail_source.blob.id
    assert_not_equal original_display_id, store.thumbnail.blob.id
    reedited_source_id = store.thumbnail_source.blob.id
    reedited_display_id = store.thumbnail.blob.id

    patch admin_store_path(store), params: {
      store: { description: "差し替え" },
      image_pair: replace_pair_params(store, color: "orange")
    }

    assert_redirected_to dashboard_path
    store.reload
    assert_equal "差し替え", store.description
    assert_not_equal reedited_source_id, store.thumbnail_source.blob.id
    assert_not_equal reedited_display_id, store.thumbnail.blob.id

    perform_enqueued_jobs do
      patch admin_store_path(store), params: {
        store: { description: "削除後" },
        image_pair: delete_pair_params(store)
      }
    end

    assert_redirected_to dashboard_path
    store.reload
    assert_equal "削除後", store.description
    assert_not store.thumbnail_source.attached?
    assert_not store.thumbnail.attached?
    assert_equal({}, store.thumbnail_crop_data)
  end

  test "invalid image pair keeps existing images and normal attributes" do
    admin, store = create_store_admin_and_store(
      "store_image_pair_invalid",
      description: "更新前"
    )
    install_pair(store)
    store.reload
    previous_ids = pair_ids(store)
    blob_count = ActiveStorage::Blob.count
    sign_in admin, scope: :user

    patch admin_store_path(store), params: {
      store: { description: "保存されない" },
      image_pair: replace_pair_params(store, display: jpeg_upload(1024, 1024))
    }

    assert_redirected_to edit_admin_store_path(store)
    store.reload
    assert_equal "更新前", store.description
    assert_equal previous_ids, pair_ids(store)
    assert_equal blob_count, ActiveStorage::Blob.count
  end

  test "stale image pair returns conflict and removes newly staged blobs" do
    admin, store = create_store_admin_and_store(
      "store_image_pair_stale",
      description: "更新前"
    )
    install_pair(store)
    store.reload
    previous_ids = pair_ids(store)
    blob_count = ActiveStorage::Blob.count
    stale = reedit_pair_params(store)
    stale[:expected] = stale.fetch(:expected).merge(
      display_blob_id: store.thumbnail.blob.id + 1
    )
    sign_in admin, scope: :user

    patch admin_store_path(store),
          params: {
            store: { description: "保存されない" },
            image_pair: stale
          },
          headers: { "ACCEPT" => "application/json" }

    assert_response :conflict
    response_body = JSON.parse(response.body)
    assert_equal "image_pair_stale", response_body.fetch("error")
    assert_equal false, response_body.fetch("retryable")
    assert_includes response_body.fetch("message"), "画像が別の操作で更新されました"
    store.reload
    assert_equal "更新前", store.description
    assert_equal previous_ids, pair_ids(store)
    assert_equal blob_count, ActiveStorage::Blob.count
  end

  test "store update rejects legacy and image pair uploads together" do
    admin, store = create_store_admin_and_store(
      "store_image_pair_mixed",
      description: "更新前"
    )
    blob_count = ActiveStorage::Blob.count
    sign_in admin, scope: :user

    patch admin_store_path(store),
          params: {
            store: {
              description: "保存されない",
              thumbnail: image_upload("sample.jpg", "image/jpeg")
            },
            image_pair: replace_pair_params(store)
          },
          headers: { "ACCEPT" => "application/json" }

    assert_response :unprocessable_entity
    response_body = JSON.parse(response.body)
    assert_equal "store_update_invalid", response_body.fetch("error")
    assert_includes response_body.fetch("message"), "新旧の画像更新を同時に送信できません"
    store.reload
    assert_equal "更新前", store.description
    assert_not store.thumbnail_source.attached?
    assert_not store.thumbnail.attached?
    assert_equal blob_count, ActiveStorage::Blob.count
  end

  private

  def create_store_admin_and_store(prefix, **attributes)
    admin = User.create!(
      email: "#{prefix}@example.com",
      password: "password",
      password_confirmation: "password",
      role: :store_admin
    )
    store = Store.create!({ name: "画像店舗" }.merge(attributes))
    StoreMembership.create!(store:, user: admin, membership_role: :admin)
    [ admin, store ]
  end

  def image_upload(filename, content_type)
    fixture_file_upload(Rails.root.join("test/fixtures/files", filename), content_type)
  end

  def install_pair(store)
    ImageAttachments::MultipartUpdateService.new(
      record: store,
      purpose: :thumbnail,
      payload: replace_pair_params(store)
    ).call
  end

  def replace_pair_params(store, display: nil, color: "purple")
    {
      operation: "replace",
      source: jpeg_upload(1200, 630, color:),
      display: display || jpeg_upload(1200, 630, color:),
      crop_data: JSON.generate(crop_data),
      expected: snapshot_hash(store)
    }
  end

  def reedit_pair_params(store)
    {
      operation: "reedit",
      display: jpeg_upload(1200, 630, color: "green"),
      crop_data: JSON.generate(crop_data),
      expected: snapshot_hash(store)
    }
  end

  def delete_pair_params(store)
    {
      operation: "delete",
      crop_data: "",
      expected: snapshot_hash(store)
    }
  end

  def snapshot_hash(store)
    ImageAttachments::StagedPairUpdateService.capture(record: store, purpose: :thumbnail).to_h
  end

  def crop_data
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

  def jpeg_upload(width, height, color: "purple")
    tempfile = Tempfile.new([ "store-image", ".jpg" ]).tap { |file| @tempfiles << file }
    MiniMagick.convert do |command|
      command.size("#{width}x#{height}")
      command << "xc:#{color}"
      command << "JPEG:#{tempfile.path}"
    end
    tempfile.binmode
    tempfile.rewind
    Rack::Test::UploadedFile.new(tempfile.path, "image/jpeg", true, original_filename: "store.jpg")
  end

  def assert_complete_pair(store)
    assert store.thumbnail_source.attached?
    assert store.thumbnail.attached?
    assert_not_equal store.thumbnail_source.blob.id, store.thumbnail.blob.id
    assert_equal store.thumbnail_source.blob.id, store.thumbnail_crop_data.fetch("sourceBlobId")
  end

  def pair_ids(store)
    [
      store.thumbnail_source.blob.id,
      store.thumbnail.blob.id,
      store.thumbnail_crop_data.fetch("sourceBlobId")
    ]
  end
end
