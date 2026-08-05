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
    @actor = User.create!(
      email: "mailer-actor@example.com",
      password: "password",
      role: :store_admin,
      display_name: "Mailer Agent"
    )
    @token = @user.send(:set_reset_password_token)
  end

  test "new user instructions contain the actor, setup links, and delivery notice" do
    mail = StoreAdminRegistrationMailer.with(
      user: @user,
      store: @store,
      actor: @actor,
      reset_password_token: @token,
      registration_status: :created
    ).new_user_instructions

    assert_equal [ @user.email ], mail.to
    assert_includes mail.subject, "パスワードを設定"
    [ mail.text_part.body.decoded, mail.html_part.body.decoded ].each do |body|
      assert_includes body, @store.name
      assert_includes body, @user.email
      assert_includes body, "#{@actor.display_name}によって"
      assert_not_includes body, "営業支援会社によって"
      assert_includes body, "/users/password/edit?reset_password_token="
      assert_includes body, "有効期限は、発行から6時間"
      assert_includes body, "/users/password/new?reset_password_token="
      assert_includes body, "新しいパスワード設定メールを再送"
      assert_includes body, "本メールは送信専用です"
      assert_includes body, "オフィスUTQが運営しています"
      assert_not_includes body, "/users/sign_in"
      assert_not_includes body, "振込先口座"
      assert_not_includes body, "キャストを招待"
      assert_not_includes body, "このメールに仮パスワードは記載していません"
      assert_not_includes body, "internal-random-password"
    end
  end

  test "new user instructions use a generic actor name when display name is blank" do
    @actor.update!(display_name: nil)
    mail = StoreAdminRegistrationMailer.with(
      user: @user,
      store: @store,
      actor: @actor,
      reset_password_token: @token,
      registration_status: :created
    ).new_user_instructions

    [ mail.text_part.body.decoded, mail.html_part.body.decoded ].each do |body|
      assert_includes body, "営業支援担当者によって"
      assert_not_includes body, @actor.email
    end
  end

  test "existing user instructions contain login and password reset guidance" do
    mail = StoreAdminRegistrationMailer.with(
      user: @user,
      store: @store,
      actor: @actor,
      reset_password_token: @token,
      registration_status: :added_to_store
    ).existing_user_instructions

    assert_equal [ @user.email ], mail.to
    [ mail.text_part.body.decoded, mail.html_part.body.decoded ].each do |body|
      assert_includes body, @store.name
      assert_includes body, "/users/sign_in"
      assert_includes body, "/users/password/edit?reset_password_token="
      assert_includes body, "有効期限は発行から6時間"
      assert_includes body, "/users/password/new?reset_password_token="
      assert_includes body, "新しいパスワード設定メールを再送"
      assert_includes body, "振込先口座"
      assert_includes body, "本メールは送信専用です"
      assert_includes body, "オフィスUTQが運営しています"
    end
  end
end
