# frozen_string_literal: true

require "test_helper"

class StoreAdminRegistrationMailerTest < ActionMailer::TestCase
  setup do
    @store = Store.create!(name: "Mailer Store")
    @user = User.create!(
      email: "mailer-responsible@example.com",
      password: "internal-random-password",
      role: :store_admin,
      display_name: "Mailer Person"
    )
    @token = @user.send(:set_reset_password_token)
  end

  test "new user instructions contain setup and store guidance without a temporary password" do
    mail = StoreAdminRegistrationMailer.with(
      user: @user,
      store: @store,
      reset_password_token: @token,
      registration_status: :created
    ).new_user_instructions

    assert_equal [ @user.email ], mail.to
    assert_includes mail.subject, "パスワードを設定"
    [ mail.text_part.body.decoded, mail.html_part.body.decoded ].each do |body|
      assert_includes body, @store.name
      assert_includes body, @user.email
      assert_includes body, "/users/password/edit?reset_password_token="
      assert_includes body, "有効期限は発行から6時間"
      assert_includes body, "/users/password/new"
      assert_includes body, "振込先口座"
      assert_includes body, "キャストを招待"
      assert_not_includes body, "internal-random-password"
    end
  end

  test "existing user instructions contain login and password reset guidance" do
    mail = StoreAdminRegistrationMailer.with(
      user: @user,
      store: @store,
      reset_password_token: @token,
      registration_status: :added_to_store
    ).existing_user_instructions

    assert_equal [ @user.email ], mail.to
    [ mail.text_part.body.decoded, mail.html_part.body.decoded ].each do |body|
      assert_includes body, @store.name
      assert_includes body, "/users/sign_in"
      assert_includes body, "/users/password/edit?reset_password_token="
      assert_includes body, "有効期限は発行から6時間"
      assert_includes body, "/users/password/new"
      assert_includes body, "振込先口座"
    end
  end
end
