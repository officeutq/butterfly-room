# frozen_string_literal: true

require "test_helper"

class ImageUploadUiTest < ActionDispatch::IntegrationTest
  ACCEPTED_FILE_TYPES = ".jpg,.jpeg,.png,.webp,.heic,.heif," \
                        "image/jpeg,image/png,image/webp,image/heic,image/heif"

  test "store thumbnail uses the common validated image upload UI" do
    store_admin = create_user("image-ui-store-admin", :store_admin)
    store = Store.create!(name: "画像UI店舗")
    StoreMembership.create!(store:, user: store_admin, membership_role: :admin)

    sign_in store_admin, scope: :user
    get edit_admin_store_path(store)

    assert_response :success
    assert_image_upload_ui(
      input_name: "store[thumbnail]",
      remove_name: "store[remove_thumbnail]"
    )
  end

  test "booth thumbnail uses the common validated image upload UI" do
    cast = create_user("image-ui-cast", :cast)
    store = Store.create!(name: "画像UIブース店舗")
    booth = Booth.create!(store:, name: "画像UIブース")
    BoothCast.create!(booth:, cast_user: cast)

    sign_in cast, scope: :user
    get edit_cast_booth_path(booth)

    assert_response :success
    assert_image_upload_ui(
      input_name: "booth[thumbnail_image]",
      remove_name: "booth[remove_thumbnail_image]"
    )
  end

  test "profile avatar uses the common validated image upload UI" do
    customer = create_user("image-ui-customer", :customer)

    sign_in customer, scope: :user
    get edit_profile_path

    assert_response :success
    assert_image_upload_ui(
      input_name: "user[avatar]",
      remove_name: "user[remove_avatar]"
    )
  end

  private

  def create_user(prefix, role)
    User.create!(
      email: "#{prefix}@example.com",
      password: "password",
      password_confirmation: "password",
      role:
    )
  end

  def assert_image_upload_ui(input_name:, remove_name:)
    assert_select(
      "script[src='/vendor/filepond/filepond-plugin-file-validate-type.min.js']",
      count: 1
    )
    assert_select(
      "input[type='file'][name='#{input_name}']" \
      "[accept='#{ACCEPTED_FILE_TYPES}'][data-image-upload-target='input']",
      count: 1
    )
    assert_select(
      "input[type='hidden'][name='#{remove_name}']" \
      "[data-image-upload-target='removeFlag'][value='0']",
      count: 1
    )
    assert_select ".image-upload-help", count: 1, text: /サーバー側でJPEGへ変換/
    assert_select(
      ".image-upload-error[role='alert'][data-image-upload-target='error'][hidden]",
      count: 1
    )
  end
end
