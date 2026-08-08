# frozen_string_literal: true

require "test_helper"

class Admin::BoothCreateWithCastAssignmentTest < ActionDispatch::IntegrationTest
  include ActionDispatch::TestProcess

  setup do
    fake_ivs_client = Object.new
    fake_ivs_client.define_singleton_method(:create_stage!) do |name:, tags: {}|
      "arn:aws:ivsrealtime:ap-northeast-1:123456789012:stage/FAKE"
    end

    Ivs::Client.factory = ->(region:) { fake_ivs_client }
  end

  teardown do
    Ivs::Client.reset_factory!
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

  private

  def image_upload(filename, content_type)
    fixture_file_upload(Rails.root.join("test/fixtures/files", filename), content_type)
  end
end
