# frozen_string_literal: true

require "test_helper"

class GuestAuthPromptTest < ActionDispatch::IntegrationTest
  test "guest receives the login prompt in the modal frame" do
    get guest_auth_prompt_path, headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_select "turbo-frame#modal[data-controller='modal']"
    assert_select "h1", text: "ログインが必要です"
    assert_select "p", text: /ログインまたは視聴者アカウントの新規作成が必要です/
    assert_select "button[data-action='click->modal#close']", text: "キャンセル"
    assert_select "a[href=?][data-turbo-frame='_top']", welcome_path, text: "ログイン・新規作成へ"
  end

  test "guest direct access falls back to welcome" do
    get guest_auth_prompt_path

    assert_redirected_to welcome_path
  end

  test "signed in user is redirected to the normal home" do
    user = User.create!(email: "auth-prompt-signed-in@example.com", password: "password", role: :customer)
    sign_in user, scope: :user

    get guest_auth_prompt_path

    assert_redirected_to root_path
  end
end
