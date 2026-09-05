# frozen_string_literal: true

require "test_helper"

class SystemAdminImageUploadVerificationTest < ActionDispatch::IntegrationTest
  setup do
    @customer = User.create!(email: "image-verification-customer@example.com", password: "password", role: :customer)
    @cast = User.create!(email: "image-verification-cast@example.com", password: "password", role: :cast)
    @store_admin = User.create!(email: "image-verification-store-admin@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "image-verification-system-admin@example.com", password: "password", role: :system_admin)
  end

  test "未ログインの場合はログイン画面へ遷移する" do
    with_env("IMAGE_UPLOAD_VERIFICATION_ENABLED" => "1") do
      get system_admin_image_upload_verification_path

      assert_redirected_to new_user_session_path
    end
  end

  test "system_admin以外は有効時もアクセスできない" do
    with_env("IMAGE_UPLOAD_VERIFICATION_ENABLED" => "1") do
      [ @customer, @cast, @store_admin ].each do |user|
        sign_in user, scope: :user

        get system_admin_image_upload_verification_path

        assert_response :forbidden
        sign_out :user
      end
    end
  end

  test "有効時はsystem_adminだけがダッシュボードから検証画面へアクセスできる" do
    with_env("IMAGE_UPLOAD_VERIFICATION_ENABLED" => "1") do
      sign_in @system_admin, scope: :user

      get dashboard_path
      assert_response :success
      assert_select "a[href=?]", system_admin_image_upload_verification_path, text: /画像アップロード検証/

      get system_admin_image_upload_verification_path
      assert_response :success
      assert_select "h1", "画像アップロード検証"
      assert_select "meta[name=robots][content=?]", "noindex, nofollow"
      assert_select "[data-controller~=image-upload-verification]"
      assert_select "input[type=file][accept*='image/webp']"
      assert_select "input[type=file][accept*='image/heic'][accept*='.heif']"
      assert_select "[data-image-upload-verification-heic-worker-url-value*='image_upload_verification/heic_worker']"
      assert_select "[data-image-upload-verification-heic-decoder-url-value*='libheif-without-unsafe-eval']"
      assert_select "select[data-image-upload-verification-target=heicMode] option[value=worker]"
      assert_select "select[data-image-upload-verification-target=heicLimit] option[selected][value=standard]", text: /1600万/
      assert_select "select[data-image-upload-verification-target=heicLimit] option[value=large]", text: /3200万/
      assert_select "[data-image-upload-verification-target=heicLimitWarning][hidden]", text: /メモリ不足/
      assert_select "button[data-image-upload-verification-target=cancelConversion][disabled]"
      assert_select "select[data-image-upload-verification-target=ratio] option[value=square]", text: /1:1/
      assert_select "select[data-image-upload-verification-target=ratio] option[value=social]", text: /40:21/
      assert_select "select[data-image-upload-verification-target=normalizationQuality]", count: 0
      assert_select "select[data-image-upload-verification-target=normalizationMode]", count: 0
      assert_select "p", text: /編集元JPEGは品質0.94、長辺4096px・800万画素以下に固定/
      assert_select "[data-image-upload-verification-target=sourceDownload]"
      assert_select "textarea[data-image-upload-verification-target=normalizationReport][readonly]"
      assert_select "[data-image-upload-verification-upload-url-value=?]", system_admin_image_upload_verification_runs_path
      assert_select "[data-image-upload-verification-target~=uploadStart][disabled]"
      assert_select "[data-image-upload-verification-target=uploadTransport] option[value=direct]"
      assert_select "textarea[data-image-upload-verification-target=uploadReport][readonly]"
      assert_select ".image-upload-verification form", count: 0
    end
  end

  test "system_admin以外のダッシュボードには有効時も導線を表示しない" do
    with_env("IMAGE_UPLOAD_VERIFICATION_ENABLED" => "1") do
      [ @customer, @cast, @store_admin ].each do |user|
        sign_in user, scope: :user

        get dashboard_path

        assert_response :success
        assert_select "a[href=?]", system_admin_image_upload_verification_path, count: 0
        sign_out :user
      end
    end
  end

  test "無効時はsystem_adminにも導線を表示せず直接アクセスを404にする" do
    with_env("IMAGE_UPLOAD_VERIFICATION_ENABLED" => nil) do
      sign_in @system_admin, scope: :user

      get dashboard_path
      assert_response :success
      assert_select "a[href=?]", system_admin_image_upload_verification_path, count: 0

      get system_admin_image_upload_verification_path
      assert_response :not_found
    end
  end
end
