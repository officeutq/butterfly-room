# frozen_string_literal: true

require "test_helper"

class ProfileUpdateTest < ActionDispatch::IntegrationTest
  include ActionDispatch::TestProcess
  include ActiveJob::TestHelper

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
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
end
