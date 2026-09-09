# frozen_string_literal: true

require "test_helper"

class AdminCastsInvitationIssuedUrlTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "Invite Store")
    @store_admin = User.create!(email: "admin_invite_list@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: @store, user: @store_admin, membership_role: :admin)
    sign_in @store_admin, scope: :user
  end

  test "issuing cast invitation returns URL while list stays read only" do
    post admin_cast_invitations_path, params: { store_id: @store.id, request_key: SecureRandom.uuid }, as: :json
    assert_response :ok

    invitation = StoreCastInvitation.order(:id).last
    assert invitation.present?
    assert invitation.issued_url.present?

    assert_equal invitation.issued_url, response.parsed_body["url"]
    get admin_casts_path(tab: "invitations")
    assert_response :ok
    refute_includes response.body, invitation.issued_url
    assert_select "main [data-controller='clipboard']", count: 0
    assert_select "main [data-controller='share']", count: 0
  end

  test "issuing store_admin invitation saves issued_url and shows url + copy button in list" do
    post admin_store_admin_invitations_path
    assert_response :redirect
    follow_redirect!
    assert_response :ok

    invitation = StoreAdminInvitation.order(:id).last
    assert invitation.present?
    assert invitation.issued_url.present?

    assert_includes response.body, invitation.issued_url
    assert_includes response.body, 'data-controller="clipboard"'
    assert_includes response.body, 'data-action="click->clipboard#copy"'
    assert_includes response.body, "data-clipboard-text=\"#{invitation.issued_url}\""
  end

  test "legacy cast invitation record is visible without a URL" do
    StoreCastInvitation.create!(
      store: @store,
      invited_by_user: @store_admin,
      token_digest: StoreCastInvitation.digest_for(StoreCastInvitation.generate_token),
      expires_at: 1.week.from_now,
      note: nil,
      issued_url: nil
    )

    get admin_casts_path(tab: "invitations")
    assert_response :ok

    assert_includes response.body, "未承認"
  end

  test "legacy store_admin invitation record with nil issued_url does not error and shows placeholder" do
    StoreAdminInvitation.create!(
      store: @store,
      invited_by_user: @store_admin,
      token_digest: StoreAdminInvitation.digest_for(StoreAdminInvitation.generate_token),
      expires_at: 1.week.from_now,
      issued_url: nil
    )

    get admin_store_admin_invitations_path
    assert_response :ok

    assert_includes response.body, "（発行時に控えてください）"
  end
end
