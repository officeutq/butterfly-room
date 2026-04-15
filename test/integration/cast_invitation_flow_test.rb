# frozen_string_literal: true

require "test_helper"

class CastInvitationFlowTest < ActionDispatch::IntegrationTest
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
end
