# frozen_string_literal: true

require "test_helper"

class CastBoothSelectionReturnTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "store1")
    @booth = Booth.create!(
      store: @store,
      name: "booth1",
      status: :offline,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/test"
    )

    @cast = User.create!(email: "cast_rt@example.com", password: "password", role: :cast)
    BoothCast.create!(booth: @booth, cast_user_id: @cast.id)

    @store_admin = User.create!(email: "store_admin_booth_rt@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: @store, user: @store_admin, membership_role: :admin)
  end

  test "return_to: selecting booth redirects back to the cast page" do
    sign_in @cast, scope: :user

    get cast_booths_path(return_to: edit_cast_booth_path(@booth))
    assert_response :success

    post cast_current_booth_path, params: { booth_id: @booth.id, return_to: edit_cast_booth_path(@booth) }
    assert_response :redirect
    assert_redirected_to edit_cast_booth_path(@booth)
  end

  test "return_to_key: booth_edit redirects to the selected booth edit page" do
    sign_in @store_admin, scope: :user

    get cast_booths_path(return_to_key: "booth_edit")
    assert_response :success

    post cast_current_booth_path, params: { booth_id: @booth.id, return_to_key: "booth_edit" }
    assert_response :redirect
    assert_redirected_to edit_cast_booth_path(@booth)
  end

  test "return_to_key: booth_live redirects to the selected booth live page" do
    sign_in @cast, scope: :user

    get cast_booths_path(return_to_key: "booth_live")
    assert_response :success

    post cast_current_booth_path, params: { booth_id: @booth.id, return_to_key: "booth_live" }
    assert_response :redirect
    assert_redirected_to live_cast_booth_path(@booth)
  end

  test "invalid return_to is rejected and falls back to dashboard" do
    sign_in @cast, scope: :user

    post cast_current_booth_path, params: { booth_id: @booth.id, return_to: "//evil.example.com" }
    assert_response :redirect
    assert_redirected_to dashboard_path
  end

  test "selection from /cast/booths does not use session return_to and falls back to dashboard" do
    sign_in @cast, scope: :user

    get edit_cast_booth_path(@booth)
    assert_response :success

    get cast_booths_path
    assert_response :success

    post cast_current_booth_path,
         params: { booth_id: @booth.id },
         headers: { "HTTP_REFERER" => cast_booths_url }

    assert_response :redirect
    assert_redirected_to dashboard_path
  end
end
