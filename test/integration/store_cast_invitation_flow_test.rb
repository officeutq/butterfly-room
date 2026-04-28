# frozen_string_literal: true

require "test_helper"

class StoreCastInvitationFlowTest < ActionDispatch::IntegrationTest
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

  test "guest visiting invitation sees invitation actions and can sign up cast via invitation" do
    store = Store.create!(name: "Invite Store")
    inviter = User.create!(email: "inviter@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: store, user: inviter, membership_role: :admin)

    result = StoreCastInvitations::IssueInvitation.call!(store: store, invited_by_user: inviter, note: "note")
    token = result.token

    # 👇 ここが変更ポイント
    get cast_invitation_path(token)
    assert_response :ok
    assert_includes response.body, "キャスト招待を受ける"
    assert_includes response.body, "新規 cast アカウントを作成して招待を受ける"
    assert_includes response.body, "既存の cast アカウントで招待を受ける"

    # 招待経由 cast 新規登録へ
    get cast_sign_up_path(token: token)
    assert_response :ok

    post cast_sign_up_path(token: token), params: {
      cast_registration: {
        email: "new_cast@example.com",
        password: "password",
        password_confirmation: "password"
      }
    }

    assert_response :redirect
    follow_redirect!
    assert_response :ok
    assert_match "キャスト招待", response.body
  end

  test "cast can accept invitation once and membership is created; second accept fails" do
    store = Store.create!(name: "Invite Store")
    inviter = User.create!(email: "inviter2@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: store, user: inviter, membership_role: :admin)

    cast_user = User.create!(email: "cast@example.com", password: "password", role: :cast)

    result = StoreCastInvitations::IssueInvitation.call!(store: store, invited_by_user: inviter, note: nil)
    token = result.token

    sign_in cast_user, scope: :user

    post accept_cast_invitation_path(token)
    assert_response :redirect
    follow_redirect!
    assert_response :ok

    assert StoreMembership.exists?(store: store, user: cast_user, membership_role: :cast)

    invitation = StoreCastInvitation.find_by_token(token)
    assert invitation.used?
    assert_equal cast_user.id, invitation.accepted_by_user_id

    # 2回目は不可
    post accept_cast_invitation_path(token)
    assert_response :redirect
    follow_redirect!
    assert_response :ok
  end

  test "non-cast logged in cannot accept invitation" do
    store = Store.create!(name: "Invite Store")
    inviter = User.create!(email: "inviter3@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: store, user: inviter, membership_role: :admin)

    customer = User.create!(email: "customer@example.com", password: "password", role: :customer)

    result = StoreCastInvitations::IssueInvitation.call!(store: store, invited_by_user: inviter, note: nil)
    token = result.token

    sign_in customer, scope: :user

    get cast_invitation_path(token)
    assert_response :ok

    post accept_cast_invitation_path(token)
    assert_response :redirect
    follow_redirect!
    assert_response :ok

    assert_not StoreMembership.exists?(store: store, user: customer, membership_role: :cast)
  end

  test "expired invitation cannot be accepted" do
    store = Store.create!(name: "Invite Store")
    inviter = User.create!(email: "inviter4@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: store, user: inviter, membership_role: :admin)

    cast_user = User.create!(email: "cast2@example.com", password: "password", role: :cast)

    result = StoreCastInvitations::IssueInvitation.call!(store: store, invited_by_user: inviter, note: nil)
    token = result.token

    invitation = StoreCastInvitation.find_by_token(token)
    invitation.update!(expires_at: 1.minute.ago)

    sign_in cast_user, scope: :user

    post accept_cast_invitation_path(token)
    assert_response :redirect
    follow_redirect!
    assert_response :ok

    assert_not StoreMembership.exists?(store: store, user: cast_user, membership_role: :cast)
  end
end
