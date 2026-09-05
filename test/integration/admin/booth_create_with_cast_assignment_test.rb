# frozen_string_literal: true

require "test_helper"
require "mini_magick"
require "tempfile"

class Admin::BoothCreateWithCastAssignmentTest < ActionDispatch::IntegrationTest
  include ActionDispatch::TestProcess
  include ActiveJob::TestHelper

  setup do
    @tempfiles = []
    fake_ivs_client = Object.new
    fake_ivs_client.define_singleton_method(:create_stage!) do |name:, tags: {}|
      "arn:aws:ivsrealtime:ap-northeast-1:123456789012:stage/FAKE"
    end

    Ivs::Client.factory = ->(region:) { fake_ivs_client }
  end

  teardown do
    Ivs::Client.reset_factory!
    clear_enqueued_jobs
    clear_performed_jobs
    @tempfiles.each(&:close!)
  end

  test "store admin can create booth without cast assignment" do
    store_admin = User.create!(
      email: "store_admin_create_booth_without_cast@example.com",
      password: "password",
      password_confirmation: "password",
      role: :store_admin
    )

    store = Store.create!(name: "店舗F")
    StoreMembership.create!(store:, user: store_admin, membership_role: :admin)

    sign_in store_admin, scope: :user
    post admin_booths_path, params: {
      booth: {
        name: "キャスト未設定ブース",
        description: "説明"
      }
    }

    assert_redirected_to dashboard_path

    booth = store.booths.order(:id).last
    assert_equal "キャスト未設定ブース", booth.name
    assert_nil booth.primary_cast_user_id
  end

  test "store admin can create booth with initial cast assignment" do
    store_admin = User.create!(
      email: "store_admin_create_booth_with_cast@example.com",
      password: "password",
      password_confirmation: "password",
      role: :store_admin
    )

    cast = User.create!(
      email: "initial_assigned_cast@example.com",
      password: "password",
      password_confirmation: "password",
      role: :cast
    )

    store = Store.create!(name: "店舗G")
    StoreMembership.create!(store:, user: store_admin, membership_role: :admin)
    StoreMembership.create!(store:, user: cast, membership_role: :cast)

    sign_in store_admin, scope: :user
    post admin_booths_path, params: {
      booth: {
        name: "初回紐づけブース",
        description: "説明"
      },
      booth_cast: {
        cast_user_id: cast.id
      }
    }

    assert_redirected_to dashboard_path

    booth = store.booths.order(:id).last
    assert_equal "初回紐づけブース", booth.name
    assert_equal cast.id, booth.primary_cast_user_id
  end

  test "store admin can create booth with a HEIC thumbnail saved as JPEG" do
    store_admin = User.create!(
      email: "store_admin_create_booth_with_thumbnail@example.com",
      password: "password",
      password_confirmation: "password",
      role: :store_admin
    )
    store = Store.create!(name: "店舗J")
    StoreMembership.create!(store:, user: store_admin, membership_role: :admin)

    sign_in store_admin, scope: :user
    post admin_booths_path, params: {
      booth: {
        name: "画像付き新規ブース",
        description: "説明",
        thumbnail_image: image_upload("sample.heic", "image/png")
      }
    }

    assert_redirected_to dashboard_path

    booth = store.booths.order(:id).last
    assert booth.thumbnail_image.attached?
    assert_equal "sample.jpg", booth.thumbnail_image.filename.to_s
    assert_equal "image/jpeg", booth.thumbnail_image.content_type
    assert_equal "\xFF\xD8".b, booth.thumbnail_image.download.first(2)
  end

  test "store admin cannot create booth with cast from another store" do
    store_admin = User.create!(
      email: "store_admin_create_booth_invalid_cast@example.com",
      password: "password",
      password_confirmation: "password",
      role: :store_admin
    )

    other_cast = User.create!(
      email: "other_store_cast@example.com",
      password: "password",
      password_confirmation: "password",
      role: :cast
    )

    store = Store.create!(name: "店舗H")
    other_store = Store.create!(name: "店舗I")

    StoreMembership.create!(store:, user: store_admin, membership_role: :admin)
    StoreMembership.create!(store: other_store, user: other_cast, membership_role: :cast)

    sign_in store_admin, scope: :user
    assert_no_difference([ "Booth.count", "ActiveStorage::Blob.count" ]) do
      post admin_booths_path, params: {
        booth: {
          name: "不正キャスト指定ブース",
          description: "説明",
          thumbnail_image: image_upload("sample.heic", "image/heic")
        },
        booth_cast: {
          cast_user_id: other_cast.id
        }
      }
    end

    assert_response :unprocessable_entity
    assert_includes @response.body, "選択できないキャストです"
    assert_nil store.booths.find_by(name: "不正キャスト指定ブース")
  end

  test "store admin creates a booth image pair and initial cast in one request" do
    store_admin, store = create_store_admin("booth_pair_create")
    cast = User.create!(
      email: "booth_pair_create_cast@example.com",
      password: "password",
      password_confirmation: "password",
      role: :cast
    )
    StoreMembership.create!(store:, user: cast, membership_role: :cast)
    sign_in store_admin, scope: :user

    post admin_booths_path,
         params: {
           booth: { name: "画像組新規ブース", description: "画像と紐づけを保存" },
           booth_cast: { cast_user_id: cast.id },
           image_pair: replace_pair_params
         },
         headers: { "ACCEPT" => "application/json" }

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "complete", response_body.fetch("state")
    assert_equal dashboard_path, response_body.fetch("redirect_url")
    booth = store.booths.order(:id).last
    assert_equal "画像組新規ブース", booth.name
    assert_equal cast.id, booth.primary_cast_user_id
    assert_complete_pair(booth)
    assert_predicate booth.ivs_stage_arn, :present?
  end

  test "system admin creates a booth image pair in the selected store" do
    system_admin = User.create!(
      email: "booth_pair_system_admin@example.com",
      password: "password",
      password_confirmation: "password",
      role: :system_admin
    )
    store = Store.create!(name: "システム管理者画像組店舗")
    sign_in system_admin, scope: :user
    post admin_current_store_path, params: { store_id: store.id }

    post admin_booths_path,
         params: {
           booth: { name: "システム管理者画像組ブース" },
           image_pair: replace_pair_params
         },
         headers: { "ACCEPT" => "application/json" }

    assert_response :success
    booth = store.booths.find_by!(name: "システム管理者画像組ブース")
    assert_complete_pair(booth)
    assert_predicate booth.ivs_stage_arn, :present?
  end

  test "invalid cast rolls back a new booth and its staged image pair" do
    store_admin, store = create_store_admin("booth_pair_invalid_cast")
    other_store = Store.create!(name: "別店舗")
    other_cast = User.create!(
      email: "booth_pair_invalid_cast_user@example.com",
      password: "password",
      password_confirmation: "password",
      role: :cast
    )
    StoreMembership.create!(store: other_store, user: other_cast, membership_role: :cast)
    sign_in store_admin, scope: :user

    assert_no_difference([ "Booth.count", "BoothCast.count", "ActiveStorage::Blob.count" ]) do
      post admin_booths_path,
           params: {
             booth: { name: "保存されない画像組ブース" },
             booth_cast: { cast_user_id: other_cast.id },
             image_pair: replace_pair_params
           },
           headers: { "ACCEPT" => "application/json" }
    end

    assert_response :unprocessable_entity
    response_body = JSON.parse(response.body)
    assert_equal "booth_create_invalid", response_body.fetch("error")
    assert_includes response_body.fetch("message"), "選択できないキャストです"
    assert_nil store.booths.find_by(name: "保存されない画像組ブース")
  end

  test "new booth rejects legacy and image pair uploads together" do
    store_admin, _store = create_store_admin("booth_pair_mixed")
    sign_in store_admin, scope: :user

    assert_no_difference([ "Booth.count", "ActiveStorage::Blob.count" ]) do
      post admin_booths_path,
           params: {
             booth: {
               name: "保存されない混在ブース",
               thumbnail_image: image_upload("sample.jpg", "image/jpeg")
             },
             image_pair: replace_pair_params
           },
           headers: { "ACCEPT" => "application/json" }
    end

    assert_response :unprocessable_entity
    response_body = JSON.parse(response.body)
    assert_includes response_body.fetch("message"), "新旧の画像更新を同時に送信できません"
  end

  private

  def create_store_admin(prefix)
    store_admin = User.create!(
      email: "#{prefix}@example.com",
      password: "password",
      password_confirmation: "password",
      role: :store_admin
    )
    store = Store.create!(name: "#{prefix}店舗")
    StoreMembership.create!(store:, user: store_admin, membership_role: :admin)
    [ store_admin, store ]
  end

  def replace_pair_params
    {
      operation: "replace",
      source: jpeg_upload(1200, 630),
      display: jpeg_upload(1200, 630),
      crop_data: JSON.generate(crop_data),
      expected: {
        source_attachment_id: "",
        source_blob_id: "",
        display_attachment_id: "",
        display_blob_id: ""
      }
    }
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

  def jpeg_upload(width, height)
    tempfile = Tempfile.new([ "admin-booth-image", ".jpg" ]).tap { |file| @tempfiles << file }
    MiniMagick.convert do |command|
      command.size("#{width}x#{height}")
      command << "xc:purple"
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

  def image_upload(filename, content_type)
    fixture_file_upload(Rails.root.join("test/fixtures/files", filename), content_type)
  end
end
