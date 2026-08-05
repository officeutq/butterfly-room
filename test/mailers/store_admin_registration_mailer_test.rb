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
    assert_includes mail.text_part.body.decoded, @store.name
    assert_includes mail.text_part.body.decoded, @user.email
    assert_includes mail.text_part.body.decoded, "/users/password/edit?reset_password_token="
    assert_includes mail.text_part.body.decoded, "振込先口座"
    assert_includes mail.text_part.body.decoded, "キャストを招待"
    assert_not_includes mail.text_part.body.decoded, "internal-random-password"
  end

  test "existing user instructions contain login and password reset guidance" do
    mail = StoreAdminRegistrationMailer.with(
      user: @user,
      store: @store,
      reset_password_token: @token,
      registration_status: :added_to_store
    ).existing_user_instructions

    assert_equal [ @user.email ], mail.to
    assert_includes mail.text_part.body.decoded, @store.name
    assert_includes mail.text_part.body.decoded, "/users/sign_in"
    assert_includes mail.text_part.body.decoded, "/users/password/new"
    assert_includes mail.text_part.body.decoded, "振込先口座"
  end
end
