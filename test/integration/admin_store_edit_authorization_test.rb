# frozen_string_literal: true

require "test_helper"

class AdminStoreEditAuthorizationTest < ActionDispatch::IntegrationTest
  include ActionDispatch::TestProcess
  include ActiveJob::TestHelper

  setup do
    @store1 = Store.create!(name: "store1")
    @store2 = Store.create!(name: "store2")

    @customer     = User.create!(email: "cust_s@example.com", password: "password", role: :customer)
    @store_admin  = User.create!(email: "admin_s@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "sys_s@example.com", password: "password", role: :system_admin)

    StoreMembership.create!(store: @store1, user: @store_admin, membership_role: :admin)
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "customer cannot edit/update (403)" do
    sign_in @customer, scope: :user

    get edit_admin_store_path(@store1)
    assert_response :forbidden

    patch admin_store_path(@store1), params: { store: { name: "x" } }
    assert_response :forbidden
  end

  test "store_admin can edit/update only own store (403 for others)" do
    sign_in @store_admin, scope: :user

    get edit_admin_store_path(@store1)
    assert_response :success

    get edit_admin_store_path(@store2)
    assert_response :forbidden

    patch admin_store_path(@store2), params: { store: { name: "x" } }
    assert_response :forbidden
  end

  test "system_admin can edit/update any store" do
    sign_in @system_admin, scope: :user

    get edit_admin_store_path(@store1)
    assert_response :success

    patch admin_store_path(@store2), params: { store: { name: "sys updated" } }
    assert_response :redirect
    assert_redirected_to dashboard_path
    assert_equal "sys updated", @store2.reload.name
  end

  test "system_admin sees and can update sales support company setting" do
    sign_in @system_admin, scope: :user

    get edit_admin_store_path(@store1)

    assert_response :success
    assert_select "input[name='store[sales_support_company]']"

    patch admin_store_path(@store1), params: { store: { sales_support_company: "1" } }
    assert_redirected_to dashboard_path
    assert @store1.reload.sales_support_company?

    patch admin_store_path(@store1), params: { store: { sales_support_company: "0" } }
    assert_redirected_to dashboard_path
    assert_not @store1.reload.sales_support_company?
  end

  test "store_admin neither sees nor can update sales support company setting" do
    sign_in @store_admin, scope: :user

    get edit_admin_store_path(@store1)

    assert_response :success
    assert_select "input[name='store[sales_support_company]']", count: 0

    patch admin_store_path(@store1), params: { store: { sales_support_company: "1" } }
    assert_redirected_to dashboard_path
    assert_not @store1.reload.sales_support_company?
  end

  test "store_admin can update fields and attach thumbnail" do
    sign_in @store_admin, scope: :user

    file = image_upload("sample.heic", "image/png")

    patch admin_store_path(@store1), params: {
      store: {
        name: "store1 updated",
        description: "desc",
        area: "渋谷",
        business_type: "girls_bar",
        thumbnail: file
      }
    }

    assert_response :redirect
    assert_redirected_to dashboard_path

    @store1.reload
    assert_equal "store1 updated", @store1.name
    assert_equal "desc", @store1.description
    assert_equal "渋谷", @store1.area
    assert_equal "girls_bar", @store1.business_type
    assert @store1.thumbnail.attached?
    assert_equal "sample.jpg", @store1.thumbnail.filename.to_s
    assert_equal "image/jpeg", @store1.thumbnail.content_type
    assert_equal "\xFF\xD8".b, @store1.thumbnail.download.first(2)
  end

  test "store_admin can replace thumbnail and a new upload wins over removal" do
    old_blob = attach_existing_thumbnail
    sign_in @store_admin, scope: :user

    perform_enqueued_jobs do
      patch admin_store_path(@store1), params: {
        store: {
          thumbnail: image_upload("sample.webp", "image/webp"),
          remove_thumbnail: "1"
        }
      }
    end

    assert_redirected_to dashboard_path

    @store1.reload
    assert @store1.thumbnail.attached?
    assert_not_equal old_blob.id, @store1.thumbnail.blob.id
    assert_not ActiveStorage::Blob.exists?(old_blob.id)
  end

  test "store_admin can remove thumbnail" do
    old_blob = attach_existing_thumbnail
    sign_in @store_admin, scope: :user

    perform_enqueued_jobs do
      patch admin_store_path(@store1), params: { store: { remove_thumbnail: "1" } }
    end

    assert_redirected_to dashboard_path
    assert_not @store1.reload.thumbnail.attached?
    assert_not ActiveStorage::Blob.exists?(old_blob.id)
  end

  test "store image conversion failure keeps existing thumbnail and attributes" do
    old_blob = attach_existing_thumbnail
    sign_in @store_admin, scope: :user

    patch admin_store_path(@store1), params: {
      store: {
        name: "保存されない店舗名",
        thumbnail: image_upload("corrupt.heic", "image/heic")
      }
    }

    assert_redirected_to edit_admin_store_path(@store1)

    @store1.reload
    assert_equal "store1", @store1.name
    assert_equal old_blob.id, @store1.thumbnail.blob.id
  end

  test "store update without an image keeps its existing blob" do
    old_blob = attach_existing_thumbnail
    sign_in @store_admin, scope: :user

    assert_no_difference("ActiveStorage::Blob.count") do
      patch admin_store_path(@store1), params: { store: { name: "画像未変更店舗" } }
    end

    assert_redirected_to dashboard_path
    assert_equal old_blob.id, @store1.reload.thumbnail.blob.id
  end

  test "store_admin can update basic info fields" do
    sign_in @store_admin, scope: :user

    result = Struct.new(:latitude, :longitude, :coordinates).new(
      32.8061463,
      130.7058304,
      [ 32.8061463, 130.7058304 ]
    )

    original_search = Geocoder.method(:search)

    Geocoder.define_singleton_method(:search) do |*_args|
      [ result ]
    end

    patch admin_store_path(@store1), params: {
      store: {
        name: "store1 updated",
        description: "desc",
        area: "渋谷",
        business_type: "girls_bar",
        address: "熊本県熊本市中央区本丸1-1",
        phone_number: "090-1111-2222",
        business_hours: "平日 19:00〜1:00",
        website_url: "https://officeutq.co.jp",
        x_url: "https://x.com/Butterflyve_jp",
        instagram_url: "https://www.instagram.com/butterflyve_0315/",
        tiktok_url: "https://www.tiktok.com/@aespa_official",
        youtube_url: "https://www.youtube.com/@SleepRelaxingHealingMusic"
      }
    }

    assert_response :redirect
    assert_redirected_to dashboard_path

    @store1.reload
    assert_equal "store1 updated", @store1.name
    assert_equal "desc", @store1.description
    assert_equal "渋谷", @store1.area
    assert_equal "girls_bar", @store1.business_type
    assert_equal "熊本県熊本市中央区本丸1-1", @store1.address
    assert_equal "090-1111-2222", @store1.phone_number
    assert_equal "平日 19:00〜1:00", @store1.business_hours
    assert_equal "https://officeutq.co.jp", @store1.website_url
    assert_equal "https://x.com/Butterflyve_jp", @store1.x_url
    assert_equal "https://www.instagram.com/butterflyve_0315/", @store1.instagram_url
    assert_equal "https://www.tiktok.com/@aespa_official", @store1.tiktok_url
    assert_equal "https://www.youtube.com/@SleepRelaxingHealingMusic", @store1.youtube_url
    assert_not_nil @store1.latitude
    assert_not_nil @store1.longitude
  ensure
    Geocoder.define_singleton_method(:search, original_search)
  end

  private

  def attach_existing_thumbnail
    File.open(file_fixture("sample.jpg"), "rb") do |io|
      @store1.thumbnail.attach(
        io:,
        filename: "old-store.jpg",
        content_type: "image/jpeg",
        identify: false
      )
    end

    @store1.thumbnail.blob
  end

  def image_upload(filename, content_type)
    fixture_file_upload(Rails.root.join("test/fixtures/files", filename), content_type)
  end
end
