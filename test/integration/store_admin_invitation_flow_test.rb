# frozen_string_literal: true

require "test_helper"

class StoreAdminInvitationFlowTest < ActionDispatch::IntegrationTest
  test "guest visiting store_admin invitation sees invitation actions and can sign up store_admin via invitation" do
    store = Store.create!(name: "Invite Store")
    inviter = User.create!(email: "inviter_admin@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: store, user: inviter, membership_role: :admin)

    result = StoreAdminInvitations::IssueInvitation.call!(store: store, invited_by_user: inviter)
    token = result.token

    get store_admin_invitation_path(token)
    assert_response :ok
    assert_includes response.body, "store_admin 招待を受ける"
    assert_includes response.body, "新規 store_admin アカウントを作成して招待を受ける"
    assert_includes response.body, "既存の store_admin アカウントで招待を受ける"

    # 招待経由 store_admin 新規登録へ
    get store_admin_sign_up_path(token: token)
    assert_response :ok

    post store_admin_sign_up_path(token: token), params: {
      store_admin_registration: {
        email: "new_store_admin@example.com",
        password: "password",
        password_confirmation: "password"
      }
    }
    assert_response :redirect
    follow_redirect!
    assert_response :ok
    assert_match "store_admin 招待", response.body
  end

  test "store_admin can accept invitation once and membership is created; second accept fails; current_store is set" do
    store = Store.create!(name: "Invite Store")
    inviter = User.create!(email: "inviter_admin2@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: store, user: inviter, membership_role: :admin)

    store_admin_user = User.create!(email: "store_admin@example.com", password: "password", role: :store_admin)

    result = StoreAdminInvitations::IssueInvitation.call!(store: store, invited_by_user: inviter)
    token = result.token

    sign_in store_admin_user, scope: :user

    post accept_store_admin_invitation_path(token)
    assert_response :redirect
    follow_redirect!
    assert_response :ok

    assert StoreMembership.exists?(store: store, user: store_admin_user, membership_role: :admin)

    invitation = StoreAdminInvitation.find_by_token(token)
    assert invitation.used?
    assert_equal store_admin_user.id, invitation.accepted_by_user_id

    # current_store が招待対象にセットされている（重要）
    assert_equal store.id, @request.session[:current_store_id].to_i

    # 2回目は不可
    post accept_store_admin_invitation_path(token)
    assert_response :redirect
    follow_redirect!
    assert_response :ok
  end

  test "non-store_admin logged in cannot accept store_admin invitation" do
    store = Store.create!(name: "Invite Store")
    inviter = User.create!(email: "inviter_admin3@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: store, user: inviter, membership_role: :admin)

    customer = User.create!(email: "customer_for_admin_invite@example.com", password: "password", role: :customer)

    result = StoreAdminInvitations::IssueInvitation.call!(store: store, invited_by_user: inviter)
    token = result.token

    sign_in customer, scope: :user

    get store_admin_invitation_path(token)
    assert_response :ok

    post accept_store_admin_invitation_path(token)
    assert_response :redirect
    follow_redirect!
    assert_response :ok

    assert_not StoreMembership.exists?(store: store, user: customer, membership_role: :admin)
  end

  test "expired store_admin invitation cannot be accepted" do
    store = Store.create!(name: "Invite Store")
    inviter = User.create!(email: "inviter_admin4@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: store, user: inviter, membership_role: :admin)

    store_admin_user = User.create!(email: "store_admin2@example.com", password: "password", role: :store_admin)

    result = StoreAdminInvitations::IssueInvitation.call!(store: store, invited_by_user: inviter)
    token = result.token

    invitation = StoreAdminInvitation.find_by_token(token)
    invitation.update!(expires_at: 1.minute.ago)

    sign_in store_admin_user, scope: :user

    post accept_store_admin_invitation_path(token)
    assert_response :redirect
    follow_redirect!
    assert_response :ok

    assert_not StoreMembership.exists?(store: store, user: store_admin_user, membership_role: :admin)
  end
end
