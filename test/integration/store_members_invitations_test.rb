# frozen_string_literal: true

require "test_helper"

class StoreMembersInvitationsTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "所属店舗", onboarding_step: :invite_cast)
    @admin = User.create!(email: "members-admin@example.test", password: "password", role: :store_admin, display_name: "店舗管理者本人")
    @membership = StoreMembership.create!(store: @store, user: @admin, membership_role: :admin)
    sign_in @admin
  end

  test "dashboard and three tabs include admins without cast removal actions" do
    cast = User.create!(email: "members-cast@example.test", password: "password", role: :cast, display_name: "所属キャスト本人")
    membership = StoreMembership.create!(store: @store, user: cast, membership_role: :cast)
    other = Store.create!(name: "別店舗")
    outsider = User.create!(email: "members-other@example.test", password: "password", role: :store_admin, display_name: "別店舗管理者")
    StoreMembership.create!(store: other, user: outsider, membership_role: :admin)
    get dashboard_path
    assert_select "a[href=?]", admin_casts_path, text: /店舗所属者情報/
    get admin_casts_path
    assert_response :ok
    assert_select "nav[aria-label='店舗所属者情報の切り替え'] a", count: 3
    assert_select "[data-membership-role='admin']", text: /店舗管理者本人/ do
      assert_select "form", count: 0
      assert_select ".small", text: "所属ブース", count: 0
    end
    assert_select "[data-membership-role='cast'] form[action=?]", admin_cast_path(membership)
    refute_includes response.body, "別店舗管理者"
    assert_no_difference "StoreMembership.count" do
      delete admin_cast_path(@membership)
    end
    assert_response :not_found
  end

  test "empty invitation tabs offer modals and old manager URL redirects" do
    { "invitations" => new_admin_cast_invitation_path(selection_store_id: @store.id),
      "admin_invitations" => new_admin_store_admin_invitation_path(selection_store_id: @store.id) }.each do |tab, path|
      get admin_casts_path(tab: tab)
      label = tab == "invitations" ? "キャスト招待URLを発行" : "店舗管理者招待URLを発行"
      assert_select "a[href=?][data-turbo-frame='modal']", path, text: label
    end
    get admin_store_admin_invitations_path
    assert_redirected_to admin_casts_path(tab: "admin_invitations")
    assert_equal "invite_cast", @store.reload.onboarding_step
  end

  test "manager modal GET does not issue and POST retry preserves one URL" do
    assert_no_difference "StoreAdminInvitation.count" do
      get new_admin_store_admin_invitation_path(selection_store_id: @store.id), headers: { "Turbo-Frame" => "modal" }
      assert_response :ok
      assert_select "[data-invitation-modal-admin-value='true']"
      assert_select "[data-onboarding-target-element]", count: 0
    end
    key = SecureRandom.uuid
    assert_difference "StoreAdminInvitation.count", 1 do
      issue(key: key)
      first = response.parsed_body["url"]
      issue(key: key)
      assert_equal first, response.parsed_body["url"]
    end
    assert_equal "invite_cast", @store.reload.onboarding_step
    assert_equal @store.id, response.parsed_body["store_id"]
    assert_nil response.parsed_body["step"]
    get new_admin_store_admin_invitation_path
    assert_redirected_to admin_casts_path(tab: "admin_invitations")
  end

  test "memo and sharing persist with no tutorial progress and cancel refuses shared invitations" do
    issue
    invitation = StoreAdminInvitation.last
    patch admin_store_admin_invitation_path(invitation), params: { store_admin_invitation: { note: "管理者限定メモ" } }, as: :json
    assert_response :ok
    2.times do
      post shared_admin_store_admin_invitation_path(invitation), as: :json
      assert_response :ok
    end
    assert invitation.reload.shared_at
    assert_equal "管理者限定メモ", invitation.note
    delete admin_store_admin_invitation_path(invitation), as: :json
    assert_response :conflict
    assert_not invitation.reload.cancelled?
    assert_equal "invite_cast", @store.reload.onboarding_step
    sign_out @admin
    get store_admin_invitation_path(invitation.issued_url.split("/").last)
    assert_response :ok
    refute_includes response.body, "管理者限定メモ"
  end

  test "cancel keeps history and blocks signup acceptance and existing member automatic use" do
    issue
    invitation = StoreAdminInvitation.last
    token = invitation.issued_url.split("/").last
    assert_no_difference "StoreAdminInvitation.count" do
      2.times do
        delete admin_store_admin_invitation_path(invitation), as: :json
        assert_response :ok
      end
    end
    assert invitation.reload.cancelled?
    get admin_casts_path(tab: "admin_invitations")
    refute_includes response.body, invitation.issued_url
    get store_admin_invitation_path(token)
    assert_includes response.body, "取消済み"
    assert_not invitation.reload.used?
    sign_out @admin
    get store_admin_invitation_path(token)
    assert_select "a[href=?]", store_admin_sign_up_path(token: token), count: 0
    assert_no_difference "User.count" do
      post store_admin_sign_up_path(token: token), params: { store_admin_registration: { email: "cancelled-signup@example.test", password: "password", password_confirmation: "password" } }
    end
    assert_redirected_to store_admin_invitation_path(token)
    recipient = User.create!(email: "cancelled-recipient@example.test", password: "password", role: :store_admin)
    sign_in recipient
    assert_no_difference "StoreMembership.count" do
      post accept_store_admin_invitation_path(token)
    end
    assert_not invitation.reload.used?
  end

  test "list includes legacy used expired and memo records but excludes another store and cancellations" do
    issue
    visible = StoreAdminInvitation.last
    visible.update!(note: "表示メモ")
    used = StoreAdminInvitations::IssueInvitation.call!(store: @store, invited_by_user: @admin).invitation
    used.update!(used_at: Time.current, accepted_by_user: @admin)
    expired = StoreAdminInvitations::IssueInvitation.call!(store: @store, invited_by_user: @admin).invitation
    expired.update!(expires_at: 1.day.ago)
    cancelled = StoreAdminInvitations::IssueInvitation.call!(store: @store, invited_by_user: @admin).invitation
    cancelled.update!(cancelled_at: Time.current, note: "取消メモ")
    other = Store.create!(name: "別店舗")
    StoreMembership.create!(store: other, user: @admin, membership_role: :admin)
    foreign = StoreAdminInvitations::IssueInvitation.call!(store: other, invited_by_user: @admin).invitation
    foreign.update!(note: "別店舗メモ")
    post admin_current_store_path, params: { store_id: @store.id }
    get admin_casts_path(tab: "admin_invitations")
    assert_response :ok
    %w[表示メモ 有効 使用済み 期限切れ].each { |text| assert_includes response.body, text }
    %w[取消メモ 別店舗メモ].each { |text| refute_includes response.body, text }
    refute_includes response.body, visible.issued_url
    assert_select "#store_invitation_list button", count: 0
  end

  test "stale list and modal cannot issue in changed store and updates stay with original invitation" do
    issue
    invitation = StoreAdminInvitation.last
    other = Store.create!(name: "切替先")
    StoreMembership.create!(store: other, user: @admin, membership_role: :admin)
    post admin_current_store_path, params: { store_id: other.id }
    get admin_casts_path(tab: "admin_invitations", selection_store_id: @store.id)
    assert_response :conflict
    get new_admin_store_admin_invitation_path(selection_store_id: @store.id), headers: { "Turbo-Frame" => "modal" }
    assert_response :ok
    assert_select "[data-redirect-url]"
    assert_select "[data-controller='invitation-modal']", count: 0
    assert_no_difference "StoreAdminInvitation.count" do
      post admin_store_admin_invitations_path, params: { store_id: @store.id, request_key: SecureRandom.uuid }, as: :json
      assert_response :conflict
    end
    patch admin_store_admin_invitation_path(invitation), params: { store_admin_invitation: { note: "元店舗のメモ" } }, as: :json
    assert_response :ok
    assert_equal @store.id, invitation.reload.store_id
    assert_equal "元店舗のメモ", invitation.note
    @membership.destroy!
    delete admin_store_admin_invitation_path(invitation), as: :json
    assert_response :not_found
    assert_not invitation.reload.cancelled?
  end

  test "system admin can issue and unrelated users cannot access the manager modal" do
    sign_out @admin
    get new_admin_store_admin_invitation_path
    assert_redirected_to new_user_session_path
    customer = User.create!(email: "invite-customer@example.test", password: "password", role: :customer)
    sign_in customer
    get new_admin_store_admin_invitation_path, headers: { "Turbo-Frame" => "modal" }
    assert_response :forbidden
    sign_out customer
    system_admin = User.create!(email: "invite-system@example.test", password: "password", role: :system_admin)
    sign_in system_admin
    post admin_current_store_path, params: { store_id: @store.id }
    issue
    assert_equal system_admin.id, StoreAdminInvitation.last.invited_by_user_id
  end

  private

  def issue(key: SecureRandom.uuid)
    post admin_store_admin_invitations_path, params: { store_id: @store.id, request_key: key }, as: :json
    assert_response :ok
  end
end
