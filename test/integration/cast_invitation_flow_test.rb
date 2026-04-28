# frozen_string_literal: true

require "test_helper"

class CastInvitationFlowTest < ActionDispatch::IntegrationTest
  setup do
    fake_ivs_client = Object.new
    fake_ivs_client.define_singleton_method(:create_stage!) do |name:, tags: {}|
      "arn:aws:ivsrealtime:ap-northeast-1:123456789012:stage/FAKE"
    end

    Ivs::Client.factory = ->(region:) { fake_ivs_client }
  end

  teardown do
    Ivs::Client.reset_factory!
  end

  test "guest visiting cast invitation sees invitation actions" do
    store = Store.create!(name: "Invite Store")
    inviter = User.create!(email: "inviter_cast_guest@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: store, user: inviter, membership_role: :admin)

    result = StoreCastInvitations::IssueInvitation.call!(store: store, invited_by_user: inviter)
    token = result.token

    get cast_invitation_path(token)

    assert_response :ok
    assert_includes response.body, "キャスト招待を受ける"
    assert_includes response.body, "新規 cast アカウントを作成して招待を受ける"
    assert_includes response.body, "既存の cast アカウントで招待を受ける"
  end

  test "cast can accept invitation and booth is auto created, linked, and set as current_booth" do
    store = Store.create!(name: "Invite Store")
    inviter = User.create!(email: "inviter_cast@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: store, user: inviter, membership_role: :admin)

    cast_user = User.create!(email: "cast_user@example.com", password: "password", role: :cast, display_name: "愛")

    result = StoreCastInvitations::IssueInvitation.call!(store: store, invited_by_user: inviter)
    token = result.token

    sign_in cast_user, scope: :user

    assert_difference -> { Booth.count }, +1 do
      assert_difference -> { BoothCast.count }, +1 do
        post accept_cast_invitation_path(token)
      end
    end

    assert_response :redirect
    follow_redirect!
    assert_response :ok

    assert StoreMembership.exists?(store: store, user: cast_user, membership_role: :cast)

    booth = Booth.order(:id).last
    assert_equal store.id, booth.store_id
    assert_equal "愛のブース", booth.name
    assert booth.ivs_stage_arn.present?

    booth_cast = BoothCast.order(:id).last
    assert_equal booth.id, booth_cast.booth_id
    assert_equal cast_user.id, booth_cast.cast_user_id

    invitation = StoreCastInvitation.find_by_token(token)
    assert invitation.used?
    assert_equal cast_user.id, invitation.accepted_by_user_id

    assert_equal booth.id, @request.session[:current_booth_id].to_i
    assert_equal store.id, @request.session[:current_store_id].to_i
  end

  test "cast without display_name gets anonymous booth name" do
    store = Store.create!(name: "Invite Store")
    inviter = User.create!(email: "inviter_cast2@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: store, user: inviter, membership_role: :admin)

    cast_user = User.create!(email: "cast_user2@example.com", password: "password", role: :cast)

    result = StoreCastInvitations::IssueInvitation.call!(store: store, invited_by_user: inviter)
    token = result.token

    sign_in cast_user, scope: :user

    post accept_cast_invitation_path(token)
    assert_response :redirect

    booth = Booth.order(:id).last
    assert_equal "ななしさんのブース", booth.name
  end

  test "existing cast is redirected to booth edit after accepting invitation, then to home after booth update" do
    store = Store.create!(name: "Invite Store")
    inviter = User.create!(email: "inviter_cast3@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: store, user: inviter, membership_role: :admin)

    cast_user = User.create!(
      email: "cast_user3@example.com",
      password: "password",
      password_confirmation: "password",
      role: :cast,
      display_name: "愛"
    )

    result = StoreCastInvitations::IssueInvitation.call!(store: store, invited_by_user: inviter)
    token = result.token

    sign_in cast_user, scope: :user

    post accept_cast_invitation_path(token)
    booth = Booth.order(:id).last

    assert_redirected_to edit_cast_booth_path(booth)
    follow_redirect!
    assert_response :success
    assert_includes @response.body, "ブース編集"

    patch cast_booth_path(booth), params: {
      booth: {
        name: "更新後ブース名",
        description: "更新後説明"
      }
    }

    assert_redirected_to root_path
  end

  test "new cast via invitation is redirected to profile edit, then booth edit, then home" do
    store = Store.create!(name: "Invite Store")
    inviter = User.create!(email: "inviter_cast4@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: store, user: inviter, membership_role: :admin)

    result = StoreCastInvitations::IssueInvitation.call!(store: store, invited_by_user: inviter)
    token = result.token

    post cast_sign_up_path, params: {
      token: token,
      cast_registration: {
        email: "new_cast_user@example.com",
        password: "password",
        password_confirmation: "password"
      }
    }

    assert_redirected_to cast_invitation_path(token)
    follow_redirect!
    assert_response :success

    post accept_cast_invitation_path(token)
    assert_redirected_to edit_profile_path
    follow_redirect!
    assert_response :success
    assert_includes @response.body, "プロフィール編集"

    booth = Booth.order(:id).last

    patch profile_path, params: {
      user: {
        display_name: "新規キャスト名",
        bio: "自己紹介です"
      }
    }

    assert_equal "新規キャスト名のブース", booth.reload.name
    assert_redirected_to edit_cast_booth_path(booth)
    follow_redirect!
    assert_response :success
    assert_includes @response.body, "ブース編集"

    patch cast_booth_path(booth), params: {
      booth: {
        name: "新しいブース名",
        description: "新しい説明"
      }
    }

    assert_redirected_to root_path
  end
end
