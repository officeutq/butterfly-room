# frozen_string_literal: true

require "test_helper"
require "mini_magick"
require "tempfile"

class ProfileUpdateTest < ActionDispatch::IntegrationTest
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

  test "profile update redirects to home with notice" do
    user = User.create!(
      email: "profile_update@example.com",
      password: "password",
      password_confirmation: "password",
      role: :customer
    )

    sign_in user, scope: :user

    patch profile_path, params: {
      user: {
        display_name: "更新後の表示名",
        bio: "更新後の自己紹介"
      }
    }

    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
    assert_includes @response.body, "プロフィールを更新しました"

    user.reload
    assert_equal "更新後の表示名", user.display_name
    assert_equal "更新後の自己紹介", user.bio
  end

  test "profile update failure redirects to edit for html request" do
    user = User.create!(
      email: "profile_update_failure@example.com",
      password: "password",
      password_confirmation: "password",
      role: :customer,
      bio: "初期bio"
    )

    sign_in user, scope: :user

    patch profile_path, params: {
      user: {
        display_name: "更新後の表示名",
        bio: "a" * 501
      }
    }

    assert_redirected_to edit_profile_path

    follow_redirect!
    assert_response :success
    assert_includes @response.body, "プロフィール編集"

    user.reload
    assert_not_equal "更新後の表示名", user.display_name
    assert_equal "初期bio", user.bio
  end

  test "profile update failure returns unprocessable_entity for turbo_stream request" do
    user = User.create!(
      email: "profile_update_failure_turbo@example.com",
      password: "password",
      password_confirmation: "password",
      role: :customer,
      bio: "初期bio"
    )

    sign_in user, scope: :user

    patch profile_path,
          params: {
            user: {
              display_name: "更新後の表示名",
              bio: "a" * 501
            }
          },
          as: :turbo_stream

    assert_response :unprocessable_entity
    assert_includes @response.body, "turbo-stream"
    assert_includes @response.body, "flash_inner"

    user.reload
    assert_not_equal "更新後の表示名", user.display_name
    assert_equal "初期bio", user.bio
  end

  test "profile update attaches a HEIC avatar as JPEG" do
    user = create_profile_user("profile_avatar_create")
    sign_in user, scope: :user

    patch profile_path, params: {
      user: {
        display_name: "画像付きユーザー",
        avatar: image_upload("sample.heic", "image/png")
      }
    }

    assert_redirected_to root_path

    user.reload
    assert_equal "画像付きユーザー", user.display_name
    assert user.avatar.attached?
    assert_equal "sample.jpg", user.avatar.filename.to_s
    assert_equal "image/jpeg", user.avatar.content_type
    assert_equal "\xFF\xD8".b, user.avatar.download.first(2)
  end

  test "profile update replaces an existing avatar and purges the old blob" do
    user = create_profile_user("profile_avatar_replace")
    old_blob = attach_existing_avatar(user)
    sign_in user, scope: :user

    perform_enqueued_jobs do
      patch profile_path, params: {
        user: {
          avatar: image_upload("sample.webp", "image/webp"),
          remove_avatar: "1"
        }
      }
    end

    assert_redirected_to root_path

    user.reload
    assert user.avatar.attached?
    assert_not_equal old_blob.id, user.avatar.blob.id
    assert_not ActiveStorage::Blob.exists?(old_blob.id)
  end

  test "profile update removes an existing avatar" do
    user = create_profile_user("profile_avatar_remove")
    old_blob = attach_existing_avatar(user)
    sign_in user, scope: :user

    perform_enqueued_jobs do
      patch profile_path, params: { user: { remove_avatar: "1" } }
    end

    assert_redirected_to root_path
    assert_not user.reload.avatar.attached?
    assert_not ActiveStorage::Blob.exists?(old_blob.id)
  end

  test "profile image conversion failure keeps existing avatar and attributes" do
    user = create_profile_user("profile_avatar_failure", bio: "更新前bio")
    old_blob = attach_existing_avatar(user)
    sign_in user, scope: :user

    patch profile_path, params: {
      user: {
        bio: "保存されないbio",
        avatar: image_upload("corrupt.heic", "image/heic")
      }
    }

    assert_redirected_to edit_profile_path

    user.reload
    assert_equal "更新前bio", user.bio
    assert_equal old_blob.id, user.avatar.blob.id
  end

  test "profile update creates avatar and cover image pairs with normal attributes" do
    user = create_profile_user("profile_image_pairs")
    sign_in user, scope: :user

    patch profile_path, params: {
      user: { display_name: "画像組ユーザー", bio: "2用途を同時保存" },
      avatar_image_pair: replace_pair_params(user:, purpose: :avatar),
      cover_image_pair: replace_pair_params(user:, purpose: :cover)
    }

    assert_redirected_to root_path
    user.reload
    assert_equal "画像組ユーザー", user.display_name
    assert_equal "2用途を同時保存", user.bio
    assert_complete_pair(user, :avatar)
    assert_complete_pair(user, :cover)
  end

  test "profile image pair update returns the redirect destination as JSON" do
    user = create_profile_user("profile_image_pair_json")
    sign_in user, scope: :user

    patch profile_path,
          params: {
            user: { bio: "JSONで保存" },
            avatar_image_pair: replace_pair_params(user:, purpose: :avatar)
          },
          headers: { "ACCEPT" => "application/json" }

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal "complete", response_body.fetch("state")
    assert_equal root_path, response_body.fetch("redirect_url")
    assert_equal "JSONで保存", user.reload.bio
    assert_complete_pair(user, :avatar)
  end

  test "profile image pairs can be re-edited, replaced and deleted independently" do
    user = create_profile_user("profile_image_pair_operations")
    install_pair(user, :avatar)
    install_pair(user, :cover)
    user.reload
    avatar_source_id = user.avatar_source.blob.id
    avatar_display_id = user.avatar.blob.id
    old_cover_source_id = user.cover_image_source.blob.id
    old_cover_display_id = user.cover_image.blob.id
    sign_in user, scope: :user

    patch profile_path, params: {
      user: { bio: "再編集と差し替え" },
      avatar_image_pair: reedit_pair_params(user:, purpose: :avatar),
      cover_image_pair: replace_pair_params(user:, purpose: :cover)
    }

    assert_redirected_to root_path
    user.reload
    assert_equal "再編集と差し替え", user.bio
    assert_equal avatar_source_id, user.avatar_source.blob.id
    assert_not_equal avatar_display_id, user.avatar.blob.id
    assert_not_equal old_cover_source_id, user.cover_image_source.blob.id
    assert_not_equal old_cover_display_id, user.cover_image.blob.id
    cover_ids = pair_ids(user, :cover)

    patch profile_path, params: {
      user: { display_name: "アバター削除後" },
      avatar_image_pair: delete_pair_params(user:, purpose: :avatar)
    }

    assert_redirected_to root_path
    user.reload
    assert_not user.avatar_source.attached?
    assert_not user.avatar.attached?
    assert_equal({}, user.avatar_crop_data)
    assert_equal cover_ids, pair_ids(user, :cover)

    patch profile_path, params: {
      user: { bio: "カバー削除後" },
      cover_image_pair: delete_pair_params(user:, purpose: :cover)
    }

    assert_redirected_to root_path
    user.reload
    assert_not user.cover_image_source.attached?
    assert_not user.cover_image.attached?
    assert_equal({}, user.cover_image_crop_data)
    assert_equal "カバー削除後", user.bio
  end

  test "new profile editor can explicitly delete a display-only legacy avatar" do
    user = create_profile_user("profile_legacy_avatar_delete")
    old_blob = attach_existing_avatar(user)
    sign_in user, scope: :user

    perform_enqueued_jobs do
      patch profile_path, params: {
        user: { bio: "" },
        avatar_image_pair: delete_pair_params(user:, purpose: :avatar)
      }
    end

    assert_redirected_to root_path
    user.reload
    assert_not user.avatar.attached?
    assert_not user.avatar_source.attached?
    assert_equal({}, user.avatar_crop_data)
    assert_not ActiveStorage::Blob.exists?(old_blob.id)
  end

  test "an invalid cover update keeps both existing pairs and normal attributes" do
    user = create_profile_user("profile_image_pair_failure", bio: "更新前")
    install_pair(user, :avatar)
    install_pair(user, :cover)
    user.reload
    previous_avatar_ids = pair_ids(user, :avatar)
    previous_cover_ids = pair_ids(user, :cover)
    blob_count = ActiveStorage::Blob.count
    sign_in user, scope: :user

    patch profile_path, params: {
      user: { bio: "保存されない" },
      avatar_image_pair: replace_pair_params(user:, purpose: :avatar),
      cover_image_pair: replace_pair_params(
        user:,
        purpose: :cover,
        display: jpeg_upload(1024, 1024)
      )
    }

    assert_redirected_to edit_profile_path
    user.reload
    assert_equal "更新前", user.bio
    assert_equal previous_avatar_ids, pair_ids(user, :avatar)
    assert_equal previous_cover_ids, pair_ids(user, :cover)
    assert_equal blob_count, ActiveStorage::Blob.count
  end

  test "a stale cover update rolls back the avatar pair and normal attributes" do
    user = create_profile_user("profile_image_pair_stale", bio: "更新前")
    install_pair(user, :avatar)
    install_pair(user, :cover)
    user.reload
    previous_avatar_ids = pair_ids(user, :avatar)
    previous_cover_ids = pair_ids(user, :cover)
    blob_count = ActiveStorage::Blob.count
    stale_cover = reedit_pair_params(user:, purpose: :cover)
    stale_cover[:expected] = stale_cover.fetch(:expected).merge(
      display_blob_id: user.cover_image.blob.id + 1
    )
    sign_in user, scope: :user

    patch profile_path,
          params: {
            user: { bio: "保存されない" },
            avatar_image_pair: replace_pair_params(user:, purpose: :avatar),
            cover_image_pair: stale_cover
          },
          headers: { "ACCEPT" => "application/json" }

    assert_response :conflict
    response_body = JSON.parse(response.body)
    assert_equal "image_pair_stale", response_body.fetch("error")
    assert_equal false, response_body.fetch("retryable")
    assert_includes response_body.fetch("message"), "画像が別の操作で更新されました"
    user.reload
    assert_equal "更新前", user.bio
    assert_equal previous_avatar_ids, pair_ids(user, :avatar)
    assert_equal previous_cover_ids, pair_ids(user, :cover)
    assert_equal blob_count, ActiveStorage::Blob.count
  end

  test "profile update rejects legacy and image pair uploads together" do
    user = create_profile_user("profile_image_pair_mixed", bio: "更新前")
    blob_count = ActiveStorage::Blob.count
    sign_in user, scope: :user

    patch profile_path, params: {
      user: {
        bio: "保存されない",
        avatar: image_upload("sample.jpg", "image/jpeg")
      },
      avatar_image_pair: replace_pair_params(user:, purpose: :avatar)
    }

    assert_redirected_to edit_profile_path
    assert_includes flash[:alert], "新旧の画像更新を同時に送信できません"
    user.reload
    assert_equal "更新前", user.bio
    assert_not user.avatar.attached?
    assert_not user.avatar_source.attached?
    assert_equal blob_count, ActiveStorage::Blob.count
  end

  test "profile image pair update requires authentication" do
    user = create_profile_user("profile_image_pair_unauthorized")

    patch profile_path, params: {
      user: { bio: "保存されない" },
      avatar_image_pair: replace_pair_params(user:, purpose: :avatar)
    }

    assert_redirected_to new_user_session_path
    assert_nil user.reload.bio
    assert_not user.avatar.attached?
  end

  test "profile edit shows current email and email change link" do
    user = User.create!(
      email: "profile_email_link@example.com",
      password: "password",
      password_confirmation: "password",
      role: :customer
    )

    sign_in user, scope: :user

    get edit_profile_path

    assert_response :success
    assert_includes @response.body, "profile_email_link@example.com"
    assert_includes @response.body, "メールアドレスを変更"
    assert_includes @response.body, edit_email_change_path
  end

  test "email change updates email with current password" do
    user = User.create!(
      email: "old_email@example.com",
      password: "password",
      password_confirmation: "password",
      role: :customer
    )

    sign_in user, scope: :user

    patch email_change_path, params: {
      user: {
        email: "new_email@example.com",
        current_password: "password"
      }
    }

    assert_redirected_to edit_profile_path
    follow_redirect!
    assert_response :success
    assert_includes @response.body, "メールアドレスを変更しました"

    user.reload
    assert_equal "new_email@example.com", user.email
  end

  test "email change does not update email with wrong current password" do
    user = User.create!(
      email: "unchanged_email@example.com",
      password: "password",
      password_confirmation: "password",
      role: :customer
    )

    sign_in user, scope: :user

    patch email_change_path, params: {
      user: {
        email: "changed_email@example.com",
        current_password: "wrong-password"
      }
    }

    assert_response :unprocessable_entity
    assert_includes @response.body, "メールアドレス変更"

    user.reload
    assert_equal "unchanged_email@example.com", user.email
  end

  private

  def create_profile_user(prefix, **attributes)
    User.create!(
      {
        email: "#{prefix}@example.com",
        password: "password",
        password_confirmation: "password",
        role: :customer
      }.merge(attributes)
    )
  end

  def attach_existing_avatar(user)
    File.open(file_fixture("sample.jpg"), "rb") do |io|
      user.avatar.attach(
        io:,
        filename: "old-avatar.jpg",
        content_type: "image/jpeg",
        identify: false
      )
    end

    user.avatar.blob
  end

  def image_upload(filename, content_type)
    fixture_file_upload(Rails.root.join("test/fixtures/files", filename), content_type)
  end

  def install_pair(user, purpose)
    ImageAttachments::MultipartUpdateService.new(
      record: user,
      purpose:,
      payload: replace_pair_params(user:, purpose:)
    ).call
  end

  def replace_pair_params(user:, purpose:, display: nil)
    dimensions = source_dimensions(purpose)
    {
      operation: "replace",
      source: jpeg_upload(*dimensions),
      display: display || jpeg_upload(*output_dimensions(purpose)),
      crop_data: JSON.generate(crop_data(purpose)),
      expected: snapshot_hash(user, purpose)
    }
  end

  def reedit_pair_params(user:, purpose:)
    {
      operation: "reedit",
      display: jpeg_upload(*output_dimensions(purpose), color: "green"),
      crop_data: JSON.generate(crop_data(purpose)),
      expected: snapshot_hash(user, purpose)
    }
  end

  def delete_pair_params(user:, purpose:)
    {
      operation: "delete",
      crop_data: "",
      expected: snapshot_hash(user, purpose)
    }
  end

  def snapshot_hash(user, purpose)
    ImageAttachments::StagedPairUpdateService.capture(record: user, purpose:).to_h
  end

  def crop_data(purpose)
    width, height = source_dimensions(purpose)
    output_width, output_height = output_dimensions(purpose)
    {
      "schemaVersion" => 1,
      "ratioKey" => purpose == :avatar ? "square" : "social",
      "source" => { "width" => width, "height" => height },
      "crop" => { "x" => 0, "y" => 0, "width" => width, "height" => height },
      "zoom" => 1.0,
      "output" => {
        "width" => output_width,
        "height" => output_height,
        "mimeType" => "image/jpeg",
        "quality" => 0.9
      }
    }
  end

  def source_dimensions(purpose)
    purpose == :avatar ? [ 1200, 1200 ] : [ 1200, 630 ]
  end

  def output_dimensions(purpose)
    purpose == :avatar ? [ 1024, 1024 ] : [ 1200, 630 ]
  end

  def jpeg_upload(width, height, color: "purple")
    tempfile = Tempfile.new([ "profile-image", ".jpg" ]).tap { |file| @tempfiles << file }
    MiniMagick.convert do |command|
      command.size("#{width}x#{height}")
      command << "xc:#{color}"
      command << "JPEG:#{tempfile.path}"
    end
    tempfile.binmode
    tempfile.rewind
    Rack::Test::UploadedFile.new(tempfile.path, "image/jpeg", true, original_filename: "profile.jpg")
  end

  def assert_complete_pair(user, purpose)
    configuration = user.image_attachment_purpose_for(purpose)
    source = user.public_send(configuration.source_attachment)
    display = user.public_send(configuration.display_attachment)
    data = user.public_send(configuration.crop_attribute)

    assert source.attached?
    assert display.attached?
    assert_not_equal source.blob.id, display.blob.id
    assert_equal source.blob.id, data.fetch("sourceBlobId")
  end

  def pair_ids(user, purpose)
    configuration = user.image_attachment_purpose_for(purpose)
    [
      user.public_send(configuration.source_attachment).blob.id,
      user.public_send(configuration.display_attachment).blob.id,
      user.public_send(configuration.crop_attribute).fetch("sourceBlobId")
    ]
  end
end
