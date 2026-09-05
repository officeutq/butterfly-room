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

  test "profile uses independent avatar and cover Cropper editors without FilePond" do
    customer = create_user("image-ui-customer", :customer)

    sign_in customer, scope: :user
    get edit_profile_path

    assert_response :success
    assert_select "script[src^='/vendor/filepond/']", count: 0
    assert_select "form[data-controller='image-pair-form'][data-action*='image-pair-form#submit'][enctype='multipart/form-data']", count: 1
    assert_select "input[type='file'][name='user[avatar]']", count: 0
    assert_select "input[name='user[remove_avatar]']", count: 0
    assert_cropper_editor(
      param_root: "avatar_image_pair",
      ratio_key: "square",
      label: "アバター画像"
    )
    assert_cropper_editor(
      param_root: "cover_image_pair",
      ratio_key: "social",
      label: "カバー画像"
    )
    assert_select "[data-image-pair-form-target='error'][role='alert'][hidden]", count: 1
    assert_select "[data-image-pair-form-target='submitButton'][data-turbo-submits-with='保存中…']", count: 1
  end

  test "profile keeps a legacy avatar visible and exposes a complete cover for re-editing" do
    customer = create_user("image-ui-current-customer", :customer)
    attach_fixture(customer.avatar, "legacy-avatar.jpg")
    attach_fixture(customer.cover_image_source, "cover-source.jpg")
    attach_fixture(customer.cover_image, "cover-display.jpg")
    customer.update!(cover_image_crop_data: {
      "schemaVersion" => 1,
      "ratioKey" => "social",
      "sourceBlobId" => customer.cover_image_source.blob.id,
      "source" => { "width" => 1200, "height" => 630 },
      "crop" => { "x" => 0, "y" => 0, "width" => 1200, "height" => 630 },
      "zoom" => 1.0,
      "output" => {
        "width" => 1200,
        "height" => 630,
        "mimeType" => "image/jpeg",
        "quality" => 0.9
      }
    })

    sign_in customer, scope: :user
    get edit_profile_path

    assert_response :success
    assert_select "#image-attachment-editor-avatar-image-pair" do
      assert_select "[data-image-attachment-editor-current-display-url-value]", count: 1
      assert_select "[data-image-attachment-editor-current-source-url-value]", count: 0
      assert_select "[data-image-attachment-editor-current-crop-data-value]", count: 0
      assert_select(
        "input[name='avatar_image_pair[expected][display_blob_id]']" \
        "[value='#{customer.avatar.blob.id}']",
        count: 1
      )
    end
    assert_select "#image-attachment-editor-cover-image-pair" do
      assert_select "[data-image-attachment-editor-current-display-url-value]", count: 1
      assert_select "[data-image-attachment-editor-current-source-url-value]", count: 1
      assert_select "[data-image-attachment-editor-current-crop-data-value]", count: 1
      assert_select(
        "[data-image-attachment-editor-current-source-blob-id-value='#{customer.cover_image_source.blob.id}']",
        count: 1
      )
    end
    assert_includes response.body, "/rails/active_storage/blobs/proxy/"
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

  def assert_cropper_editor(param_root:, ratio_key:, label:)
    assert_select(
      "section[data-controller='image-attachment-editor']" \
      "[data-image-attachment-editor-ratio-key-value='#{ratio_key}']",
      count: 1
    ) do
      assert_select "h2", text: label
      assert_select "input[name='#{param_root}[operation]']", count: 1
      assert_select "input[type='file'][name='#{param_root}[source]']", count: 1
      assert_select "input[type='file'][name='#{param_root}[display]']", count: 1
      assert_select "input[name='#{param_root}[crop_data]']", count: 1
      ImageAttachments::MultipartPayload::EXPECTED_ID_KEYS.each do |key|
        assert_select "input[name='#{param_root}[expected][#{key}]']", count: 1
      end
    end
  end

  def attach_fixture(attachment, filename)
    File.open(file_fixture("sample.jpg"), "rb") do |io|
      attachment.attach(io:, filename:, content_type: "image/jpeg", identify: false)
    end
  end
end
