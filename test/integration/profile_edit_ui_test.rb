# frozen_string_literal: true

require "test_helper"

class ProfileEditUiTest < ActionDispatch::IntegrationTest
  test "profile edit renders the integrated media preview and scroll action bar" do
    user = User.create!(
      email: "profile-edit-ui@example.com",
      password: "password",
      password_confirmation: "password",
      role: :customer,
      display_name: "プロフィール表示名",
      bio: "プロフィール自己紹介"
    )
    sign_in user, scope: :user

    get edit_profile_path

    assert_response :success
    assert_select "header#app_header .header-title", text: "プロフィール編集", count: 1
    assert_select "form#profile-edit-form[data-controller~='image-pair-form'][data-controller~='profile-edit']", count: 1 do
      assert_select ".profile-edit__action-bar", count: 1 do
        assert_select ".container.profile-edit__action-bar-inner", count: 1 do
          assert_select "a.profile-edit__back[href='#{dashboard_path}']", text: /戻る/, count: 1
          assert_select "input.profile-edit__save[type='submit'][value='保存'][disabled]", count: 1
        end
      end
      assert_select ".profile-edit__media", count: 1
      assert_profile_image_editor("cover_image_pair", "social", "cover")
      assert_profile_image_editor("avatar_image_pair", "square", "avatar")
      assert_select "input[data-profile-edit-target='displayName'][value='プロフィール表示名']", count: 1
      assert_select "textarea[data-profile-edit-target='bio']", text: "プロフィール自己紹介", count: 1
      assert_select ".profile-edit__fields .form-floating[data-bs-theme='light']", count: 2
      assert_select ".profile-edit__fields .form-text[data-bs-theme]", count: 0
      assert_select "input[type='submit'][value='更新する']", count: 0
      assert_select ".profile-edit__account", text: /profile-edit-ui@example.com/, count: 1
      assert_select ".profile-edit__withdrawal a", text: "退会する", count: 1
    end
  end

  test "system admin profile keeps account actions without withdrawal" do
    user = User.create!(
      email: "profile-edit-admin@example.com",
      password: "password",
      password_confirmation: "password",
      role: :system_admin
    )
    sign_in user, scope: :user

    get edit_profile_path

    assert_response :success
    assert_select ".profile-edit__account a[href='#{edit_email_change_path}']", text: "メールアドレスを変更"
    assert_select ".profile-edit__withdrawal", count: 0
  end

  private

  def assert_profile_image_editor(param_root, ratio_key, presentation)
    assert_select(
      "section#image-attachment-editor-#{param_root.dasherize}" \
      "[data-controller='image-attachment-editor']" \
      "[data-image-attachment-editor-keep-staged-actions-value='true']" \
      "[data-image-attachment-editor-ratio-key-value='#{ratio_key}']" \
      ".profile-image-editor--#{presentation}",
      count: 1
    ) do
      assert_select ".profile-image-editor__preview--#{presentation}", count: 1
      assert_select "dialog[data-image-attachment-editor-target='workspace'][hidden]", count: 1
      assert_select "input[data-image-attachment-editor-target='fileInput'][hidden]", count: 1
      assert_select "input[name='#{param_root}[operation]']", count: 1
      assert_select "input[name='#{param_root}[source]']", count: 1
      assert_select "input[name='#{param_root}[display]']", count: 1
      assert_select "input[name='#{param_root}[crop_data]']", count: 1
      assert_select ".profile-image-editor__image-menu", count: 1 do
        assert_select "button[data-bs-toggle='dropdown'][aria-label='#{presentation == 'cover' ? 'カバー画像' : 'アバター画像'}の操作を開く']",
                      count: 1
        assert_select ".dropdown-menu", count: 1 do
          assert_select "[data-action='image-attachment-editor#chooseFile']", text: /追加・差し替え/, count: 1
          assert_select "[data-image-attachment-editor-target='editButton']", text: /構図を編集/, count: 1
          assert_select "[data-image-attachment-editor-target='deleteButton']", text: /画像を削除/, count: 1
          assert_select "[data-image-attachment-editor-target='undoButton']", text: /変更を取り消す/, count: 1
        end
      end
      assert_select ".profile-image-editor__status[data-errors-only-status]", count: 1
    end
  end
end
