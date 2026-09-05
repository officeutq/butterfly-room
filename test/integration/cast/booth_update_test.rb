# frozen_string_literal: true

require "test_helper"
require "mini_magick"
require "tempfile"

class Cast::BoothUpdateTest < ActionDispatch::IntegrationTest
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

  test "cast booth update redirects to dashboard with notice" do
    cast = User.create!(
      email: "cast_booth_update@example.com",
      password: "password",
      password_confirmation: "password",
      role: :cast
    )

    store = Store.create!(name: "店舗A")
    booth = Booth.create!(store:, name: "更新前ブース名", description: "更新前説明")
    BoothCast.create!(booth:, cast_user: cast)

    sign_in cast, scope: :user

    patch cast_booth_path(booth), params: {
      booth: {
        name: "更新後ブース名",
        description: "更新後説明"
      }
    }

    assert_redirected_to dashboard_path
    follow_redirect!
    assert_response :success
    assert_includes @response.body, "ブースを更新しました"

    booth.reload
    assert_equal "更新後ブース名", booth.name
    assert_equal "更新後説明", booth.description
  end

  test "cast booth update failure redirects to edit for html request" do
    cast = User.create!(
      email: "cast_booth_update_failure@example.com",
      password: "password",
      password_confirmation: "password",
      role: :cast
    )

    store = Store.create!(name: "店舗B")
    booth = Booth.create!(store:, name: "更新前ブース名", description: "初期説明")
    BoothCast.create!(booth:, cast_user: cast)

    sign_in cast, scope: :user

    patch cast_booth_path(booth), params: {
      booth: {
        name: "a" * 101,
        description: "更新後説明"
      }
    }

    assert_redirected_to edit_cast_booth_path(booth)

    follow_redirect!
    assert_response :success
    assert_includes @response.body, "ブース編集"

    booth.reload
    assert_equal "更新前ブース名", booth.name
    assert_equal "初期説明", booth.description
  end

  test "cast booth update failure returns unprocessable_entity for turbo_stream request" do
    cast = User.create!(
      email: "cast_booth_update_failure_turbo@example.com",
      password: "password",
      password_confirmation: "password",
      role: :cast
    )

    store = Store.create!(name: "店舗C")
    booth = Booth.create!(store:, name: "更新前ブース名", description: "初期説明")
    BoothCast.create!(booth:, cast_user: cast)

    sign_in cast, scope: :user

    patch cast_booth_path(booth),
          params: {
            booth: {
              name: "a" * 101,
              description: "更新後説明"
            }
          },
          as: :turbo_stream

    assert_response :unprocessable_entity
    assert_includes @response.body, "turbo-stream"
    assert_includes @response.body, "flash_inner"

    booth.reload
    assert_equal "更新前ブース名", booth.name
    assert_equal "初期説明", booth.description
  end

  test "cast booth update attaches a HEIC thumbnail as JPEG" do
    cast, booth = create_cast_booth("cast_booth_thumbnail_create")
    sign_in cast, scope: :user

    patch cast_booth_path(booth), params: {
      booth: {
        name: "画像付きブース",
        thumbnail_image: image_upload("sample.heic", "image/png")
      }
    }

    assert_redirected_to dashboard_path

    booth.reload
    assert_equal "画像付きブース", booth.name
    assert booth.thumbnail_image.attached?
    assert_equal "sample.jpg", booth.thumbnail_image.filename.to_s
    assert_equal "image/jpeg", booth.thumbnail_image.content_type
    assert_equal "\xFF\xD8".b, booth.thumbnail_image.download.first(2)
  end

  test "cast booth update replaces thumbnail and a new upload wins over removal" do
    cast, booth = create_cast_booth("cast_booth_thumbnail_replace")
    old_blob = attach_existing_thumbnail(booth)
    sign_in cast, scope: :user

    perform_enqueued_jobs do
      patch cast_booth_path(booth), params: {
        booth: {
          thumbnail_image: image_upload("sample.webp", "image/webp"),
          remove_thumbnail_image: "1"
        }
      }
    end

    assert_redirected_to dashboard_path

    booth.reload
    assert booth.thumbnail_image.attached?
    assert_not_equal old_blob.id, booth.thumbnail_image.blob.id
    assert_not ActiveStorage::Blob.exists?(old_blob.id)
  end

  test "cast booth update removes thumbnail" do
    cast, booth = create_cast_booth("cast_booth_thumbnail_remove")
    old_blob = attach_existing_thumbnail(booth)
    sign_in cast, scope: :user

    perform_enqueued_jobs do
      patch cast_booth_path(booth), params: { booth: { remove_thumbnail_image: "1" } }
    end

    assert_redirected_to dashboard_path
    assert_not booth.reload.thumbnail_image.attached?
    assert_not ActiveStorage::Blob.exists?(old_blob.id)
  end

  test "booth image conversion failure keeps existing thumbnail and attributes" do
    cast, booth = create_cast_booth("cast_booth_thumbnail_failure", description: "更新前説明")
    old_blob = attach_existing_thumbnail(booth)
    sign_in cast, scope: :user

    patch cast_booth_path(booth), params: {
      booth: {
        description: "保存されない説明",
        thumbnail_image: image_upload("corrupt.heic", "image/heic")
      }
    }

    assert_redirected_to edit_cast_booth_path(booth)

    booth.reload
    assert_equal "更新前説明", booth.description
    assert_equal old_blob.id, booth.thumbnail_image.blob.id
  end

  test "cast update creates an image pair with normal attributes and returns JSON" do
    cast, booth = create_cast_booth("cast_booth_image_pair_create")
    sign_in cast, scope: :user

    patch cast_booth_path(booth),
          params: {
            booth: { name: "画像組ブース", description: "画像と一体更新" },
            image_pair: replace_pair_params(booth)
          },
          headers: { "ACCEPT" => "application/json" }

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "complete", response_body.fetch("state")
    assert_equal dashboard_path, response_body.fetch("redirect_url")
    booth.reload
    assert_equal "画像組ブース", booth.name
    assert_equal "画像と一体更新", booth.description
    assert_complete_pair(booth)
  end

  test "booth image pair can be re-edited replaced and deleted" do
    cast, booth = create_cast_booth("cast_booth_image_pair_operations")
    install_pair(booth)
    booth.reload
    original_source_id = booth.thumbnail_image_source.blob.id
    original_display_id = booth.thumbnail_image.blob.id
    sign_in cast, scope: :user

    patch cast_booth_path(booth), params: {
      booth: { description: "再編集" },
      image_pair: reedit_pair_params(booth)
    }

    assert_redirected_to dashboard_path
    booth.reload
    assert_equal "再編集", booth.description
    assert_equal original_source_id, booth.thumbnail_image_source.blob.id
    assert_not_equal original_display_id, booth.thumbnail_image.blob.id
    reedited_ids = pair_ids(booth)

    patch cast_booth_path(booth), params: {
      booth: { description: "差し替え" },
      image_pair: replace_pair_params(booth, color: "orange")
    }

    assert_redirected_to dashboard_path
    booth.reload
    assert_equal "差し替え", booth.description
    assert_not_equal reedited_ids.first, booth.thumbnail_image_source.blob.id
    assert_not_equal reedited_ids.second, booth.thumbnail_image.blob.id

    perform_enqueued_jobs do
      patch cast_booth_path(booth), params: {
        booth: { description: "削除後" },
        image_pair: delete_pair_params(booth)
      }
    end

    assert_redirected_to dashboard_path
    booth.reload
    assert_equal "削除後", booth.description
    assert_not booth.thumbnail_image_source.attached?
    assert_not booth.thumbnail_image.attached?
    assert_equal({}, booth.thumbnail_image_crop_data)
  end

  test "stale booth image update returns conflict and removes the staged blob" do
    cast, booth = create_cast_booth(
      "cast_booth_image_pair_stale",
      description: "更新前"
    )
    install_pair(booth)
    booth.reload
    previous_ids = pair_ids(booth)
    blob_count = ActiveStorage::Blob.count
    stale = reedit_pair_params(booth)
    stale[:expected] = stale.fetch(:expected).merge(
      display_blob_id: booth.thumbnail_image.blob.id + 1
    )
    sign_in cast, scope: :user

    patch cast_booth_path(booth),
          params: {
            booth: { description: "保存されない" },
            image_pair: stale
          },
          headers: { "ACCEPT" => "application/json" }

    assert_response :conflict
    response_body = JSON.parse(response.body)
    assert_equal "image_pair_stale", response_body.fetch("error")
    assert_includes response_body.fetch("message"), "画像が別の操作で更新されました"
    booth.reload
    assert_equal "更新前", booth.description
    assert_equal previous_ids, pair_ids(booth)
    assert_equal blob_count, ActiveStorage::Blob.count
  end

  test "related cast validation failure rolls back booth attributes and image pair" do
    store_admin = User.create!(
      email: "booth_pair_relation_admin@example.com",
      password: "password",
      password_confirmation: "password",
      role: :store_admin
    )
    current_cast = User.create!(
      email: "booth_pair_relation_current@example.com",
      password: "password",
      password_confirmation: "password",
      role: :cast
    )
    other_cast = User.create!(
      email: "booth_pair_relation_other@example.com",
      password: "password",
      password_confirmation: "password",
      role: :cast
    )
    store = Store.create!(name: "画像組関連店舗")
    StoreMembership.create!(store:, user: store_admin, membership_role: :admin)
    StoreMembership.create!(store:, user: current_cast, membership_role: :cast)
    StoreMembership.create!(store:, user: other_cast, membership_role: :cast)
    booth = Booth.create!(store:, name: "関連更新前", description: "更新前")
    BoothCast.create!(booth:, cast_user: current_cast)
    install_pair(booth)
    booth.reload
    previous_ids = pair_ids(booth)
    blob_count = ActiveStorage::Blob.count
    sign_in store_admin, scope: :user

    patch cast_booth_path(booth),
          params: {
            booth: { name: "保存されない", description: "保存されない" },
            booth_cast: { cast_user_id: other_cast.id },
            image_pair: replace_pair_params(booth, color: "red")
          },
          headers: { "ACCEPT" => "application/json" }

    assert_response :unprocessable_entity
    response_body = JSON.parse(response.body)
    assert_includes response_body.fetch("message"), "既にキャストが紐づいています"
    booth.reload
    assert_equal "関連更新前", booth.name
    assert_equal "更新前", booth.description
    assert_equal current_cast.id, booth.primary_cast_user_id
    assert_equal previous_ids, pair_ids(booth)
    assert_equal blob_count, ActiveStorage::Blob.count
  end

  test "cast update rejects legacy and image pair uploads together" do
    cast, booth = create_cast_booth("cast_booth_image_pair_mixed", description: "更新前")
    blob_count = ActiveStorage::Blob.count
    sign_in cast, scope: :user

    patch cast_booth_path(booth),
          params: {
            booth: {
              description: "保存されない",
              thumbnail_image: image_upload("sample.jpg", "image/jpeg")
            },
            image_pair: replace_pair_params(booth)
          },
          headers: { "ACCEPT" => "application/json" }

    assert_response :unprocessable_entity
    response_body = JSON.parse(response.body)
    assert_includes response_body.fetch("message"), "新旧の画像更新を同時に送信できません"
    assert_equal "更新前", booth.reload.description
    assert_equal blob_count, ActiveStorage::Blob.count
  end

  test "store admin can assign cast to unassigned booth from cast booth edit update" do
    store_admin = User.create!(
      email: "store_admin_assign_cast@example.com",
      password: "password",
      password_confirmation: "password",
      role: :store_admin
    )

    cast = User.create!(
      email: "assignable_cast@example.com",
      password: "password",
      password_confirmation: "password",
      role: :cast
    )

    store = Store.create!(name: "店舗D")
    StoreMembership.create!(store:, user: store_admin, membership_role: :admin)
    StoreMembership.create!(store:, user: cast, membership_role: :cast)

    booth = Booth.create!(store:, name: "未紐づけブース", description: "初期説明")

    sign_in store_admin, scope: :user

    patch cast_booth_path(booth), params: {
      booth: {
        name: "未紐づけブース更新後",
        description: "更新後説明"
      },
      booth_cast: {
        cast_user_id: cast.id
      }
    }

    assert_redirected_to dashboard_path

    booth.reload
    assert_equal "未紐づけブース更新後", booth.name
    assert_equal "更新後説明", booth.description
    assert_equal cast.id, booth.primary_cast_user_id
  end

  test "store admin cannot reassign already assigned booth from cast booth edit update" do
    store_admin = User.create!(
      email: "store_admin_reassign_cast@example.com",
      password: "password",
      password_confirmation: "password",
      role: :store_admin
    )

    current_cast = User.create!(
      email: "current_assigned_cast@example.com",
      password: "password",
      password_confirmation: "password",
      role: :cast
    )

    other_cast = User.create!(
      email: "other_assignable_cast@example.com",
      password: "password",
      password_confirmation: "password",
      role: :cast
    )

    store = Store.create!(name: "店舗E")
    StoreMembership.create!(store:, user: store_admin, membership_role: :admin)
    StoreMembership.create!(store:, user: current_cast, membership_role: :cast)
    StoreMembership.create!(store:, user: other_cast, membership_role: :cast)

    booth = Booth.create!(store:, name: "紐づけ済みブース", description: "初期説明")
    BoothCast.create!(booth:, cast_user: current_cast)

    sign_in store_admin, scope: :user

    patch cast_booth_path(booth), params: {
      booth: {
        name: "変更しようとした名前",
        description: "変更しようとした説明"
      },
      booth_cast: {
        cast_user_id: other_cast.id
      }
    }

    assert_redirected_to edit_cast_booth_path(booth)

    booth.reload
    assert_equal "紐づけ済みブース", booth.name
    assert_equal "初期説明", booth.description
    assert_equal current_cast.id, booth.primary_cast_user_id
  end

  private

  def create_cast_booth(prefix, **attributes)
    cast = User.create!(
      email: "#{prefix}@example.com",
      password: "password",
      password_confirmation: "password",
      role: :cast
    )
    store = Store.create!(name: "#{prefix}店舗")
    booth = Booth.create!(
      { store:, name: "#{prefix}ブース" }.merge(attributes)
    )
    BoothCast.create!(booth:, cast_user: cast)

    [ cast, booth ]
  end

  def attach_existing_thumbnail(booth)
    File.open(file_fixture("sample.jpg"), "rb") do |io|
      booth.thumbnail_image.attach(
        io:,
        filename: "old-booth.jpg",
        content_type: "image/jpeg",
        identify: false
      )
    end

    booth.thumbnail_image.blob
  end

  def image_upload(filename, content_type)
    fixture_file_upload(Rails.root.join("test/fixtures/files", filename), content_type)
  end

  def install_pair(booth)
    ImageAttachments::MultipartUpdateService.new(
      record: booth,
      purpose: :thumbnail,
      payload: replace_pair_params(booth)
    ).call
  end

  def replace_pair_params(booth, color: "purple")
    {
      operation: "replace",
      source: jpeg_upload(1200, 630, color:),
      display: jpeg_upload(1200, 630, color:),
      crop_data: JSON.generate(crop_data),
      expected: snapshot_hash(booth)
    }
  end

  def reedit_pair_params(booth)
    {
      operation: "reedit",
      display: jpeg_upload(1200, 630, color: "green"),
      crop_data: JSON.generate(crop_data),
      expected: snapshot_hash(booth)
    }
  end

  def delete_pair_params(booth)
    {
      operation: "delete",
      crop_data: "",
      expected: snapshot_hash(booth)
    }
  end

  def snapshot_hash(booth)
    ImageAttachments::StagedPairUpdateService.capture(record: booth, purpose: :thumbnail).to_h
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
    tempfile = Tempfile.new([ "cast-booth-image", ".jpg" ]).tap { |file| @tempfiles << file }
    MiniMagick.convert do |command|
      command.size("#{width}x#{height}")
      command << "xc:#{color}"
      command << "JPEG:#{tempfile.path}"
    end
    tempfile.binmode
    tempfile.rewind
    Rack::Test::UploadedFile.new(tempfile.path, "image/jpeg", true, original_filename: "booth.jpg")
  end

  def assert_complete_pair(booth)
    assert booth.thumbnail_image_source.attached?
    assert booth.thumbnail_image.attached?
    assert_not_equal booth.thumbnail_image_source.blob.id, booth.thumbnail_image.blob.id
    assert_equal booth.thumbnail_image_source.blob.id, booth.thumbnail_image_crop_data.fetch("sourceBlobId")
  end

  def pair_ids(booth)
    [
      booth.thumbnail_image_source.blob.id,
      booth.thumbnail_image.blob.id,
      booth.thumbnail_image_crop_data.fetch("sourceBlobId")
    ]
  end
end
