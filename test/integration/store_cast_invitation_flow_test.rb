# frozen_string_literal: true

require "test_helper"

class StoreCastInvitationFlowTest < ActionDispatch::IntegrationTest
  test "guest visiting invitation is redirected to login and can sign up cast via invitation" do
    store = Store.create!(name: "Invite Store")
    inviter = User.create!(email: "inviter@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: store, user: inviter, membership_role: :admin)

    result = StoreCastInvitations::IssueInvitation.call!(store: store, invited_by_user: inviter, note: "note")
    token = result.token

    get cast_invitation_path(token)
    assert_response :redirect
    assert_match "/users/sign_in", response.location
    assert_match "invite_token=#{token}", response.location

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

    sign_in cast_user

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

    sign_in customer

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

    sign_in cast_user

    post accept_cast_invitation_path(token)
    assert_response :redirect
    follow_redirect!
    assert_response :ok

    assert_not StoreMembership.exists?(store: store, user: cast_user, membership_role: :cast)
  end
end
