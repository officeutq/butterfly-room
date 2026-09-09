require "test_helper"

class CastInvitationManagementTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "招待テスト店舗", onboarding_step: :invite_cast)
    @admin = User.create!(email: "invite-manager@example.com", password: "password", role: :store_admin, display_name: "管理花子")
    StoreMembership.create!(store: @store, user: @admin, membership_role: :admin)
    sign_in @admin
  end

  test "modal GET never issues and single unselected store uses existing automatic selection" do
    assert_no_difference "StoreCastInvitation.count" do
      get new_admin_cast_invitation_path, headers: { "Turbo-Frame" => "modal" }
      assert_redirected_to select_modal_admin_stores_path(return_to_key: "cast_invitation")
      follow_redirect!(headers: { "Turbo-Frame" => "modal" })
      assert_redirected_to new_admin_cast_invitation_path
      follow_redirect!(headers: { "Turbo-Frame" => "modal" })
      assert_response :ok
      assert_select "[data-controller='cast-invitation']", count: 1
    end
  end

  test "multiple unselected stores select first but selected store is not reselected" do
    other = Store.create!(name: "他店舗")
    StoreMembership.create!(store: other, user: @admin, membership_role: :admin)
    get new_admin_cast_invitation_path, headers: { "Turbo-Frame" => "modal" }
    follow_redirect!(headers: { "Turbo-Frame" => "modal" })
    assert_response :ok
    assert_select "form[data-turbo-frame='modal']", count: 2
    post admin_current_store_path, params: { store_id: other.id, return_to_key: "cast_invitation" }, headers: { "Turbo-Frame" => "modal" }
    follow_redirect!(headers: { "Turbo-Frame" => "modal" })
    assert_select "[data-cast-invitation-store-id-value='#{other.id}']", count: 1
  end

  test "issue retries reuse URL and never overwrite note or extend expiry" do
    key = SecureRandom.uuid
    issue(key: key)
    payload = response.parsed_body
    invitation = StoreCastInvitation.last
    assert_equal "create_invite", @store.reload.onboarding_step
    patch admin_cast_invitation_path(invitation), params: { store_cast_invitation: { note: "管理者のみ" } }, as: :json
    assert_response :ok
    assert_no_difference "StoreCastInvitation.count" do
      issue(key: key)
    end
    assert_equal payload["url"], response.parsed_body["url"]
    assert_equal payload["expires_at"], response.parsed_body["expires_at"]
    assert_equal "管理者のみ", response.parsed_body["note"]
    assert_includes payload["text"], "招待テスト店舗の管理花子様から"
    refute_includes payload["text"], @admin.email
  end

  test "memo and updates stay bound to invitation store across selection changes" do
    issue
    invitation = StoreCastInvitation.last
    other = Store.create!(name: "切替先", onboarding_step: :invite_cast)
    StoreMembership.create!(store: other, user: @admin, membership_role: :admin)
    post admin_current_store_path, params: { store_id: other.id }
    patch admin_cast_invitation_path(invitation), params: { store_cast_invitation: { note: "非公開の管理メモ" } }, as: :json
    assert_response :ok
    post shared_admin_cast_invitation_path(invitation), as: :json
    assert_response :ok
    assert_equal "go_dashboard_for_drinks", @store.reload.onboarding_step
    assert_equal "invite_cast", other.reload.onboarding_step
    sign_out @admin
    get invitation.issued_url
    assert_response :ok
    refute_includes response.body, "非公開の管理メモ"
  end

  test "cancel is idempotent hides history and blocks guest registration and acceptance" do
    issue
    invitation = StoreCastInvitation.last
    2.times do
      delete admin_cast_invitation_path(invitation), as: :json
      assert_response :ok
    end
    assert invitation.reload.cancelled?
    assert_not invitation.usable?
    get admin_casts_path(tab: "invitations")
    assert_includes response.body, "表示できる招待はありません"
    assert StoreCastInvitation.exists?(invitation.id)
    sign_out @admin
    token = invitation.issued_url.split("/").last
    get cast_invitation_path(token)
    assert_includes response.body, "この招待は取り消されました"
    get cast_sign_up_path(token: token)
    assert_response :not_found
    cast = User.create!(email: "cancel-cast@example.com", password: "password", role: :cast)
    sign_in cast
    assert_no_difference [ "StoreMembership.count", "Booth.count" ] do
      post accept_cast_invitation_path(token)
    end
    assert_redirected_to cast_invitation_path(token)
  end

  test "shared and accepted invitations cannot be cancelled" do
    issue
    invitation = StoreCastInvitation.last
    2.times { post shared_admin_cast_invitation_path(invitation), as: :json; assert_response :ok }
    delete admin_cast_invitation_path(invitation), as: :json
    assert_response :conflict
    assert_not invitation.reload.cancelled?
    issue
    accepted = StoreCastInvitation.last
    accepted.update!(used_at: Time.current)
    delete admin_cast_invitation_path(accepted), as: :json
    assert_response :conflict
  end

  test "unauthorized stores and invitation updates are rejected" do
    other = Store.create!(name: "権限なし")
    assert_no_difference "StoreCastInvitation.count" do
      post admin_cast_invitations_path, params: { store_id: other.id, request_key: SecureRandom.uuid }, as: :json
      assert_response :not_found
    end
    sign_in @admin
    issue
    invitation = StoreCastInvitation.last
    StoreMembership.where(store: @store, user: @admin).delete_all
    patch admin_cast_invitation_path(invitation), params: { store_cast_invitation: { note: "改ざん" } }, as: :json
    assert_response :not_found
    assert_nil invitation.reload.note
  end

  test "list is read only and legacy URL redirects without advancing tutorial" do
    post admin_current_store_path, params: { store_id: @store.id }
    get admin_cast_invitations_path
    assert_redirected_to admin_casts_path(tab: "invitations")
    follow_redirect!
    assert_equal "invite_cast", @store.reload.onboarding_step
    assert_select "main form", count: 0
    get dashboard_path
    assert_select "a[href=?]", new_admin_cast_invitation_path, text: /キャスト招待/
    assert_select "a[href=?]", admin_cast_invitations_path, count: 0
  end

  test "legacy shared notification cannot progress without a concrete invitation" do
    @store.update!(onboarding_step: :create_invite)
    post cast_invitation_copied_admin_onboarding_path, as: :json
    assert_equal "create_invite", @store.reload.onboarding_step
  end

  test "list includes pending accepted and expired invitations but not cancelled or another store" do
    issue
    active = StoreCastInvitation.last
    active.update!(note: "有効なメモ")
    issue
    StoreCastInvitation.last.update!(note: "期限切れメモ", expires_at: 1.day.ago)
    issue
    StoreCastInvitation.last.update!(note: "承認済みメモ", used_at: Time.current, accepted_by_user: @admin)
    issue
    StoreCastInvitation.last.update!(note: "取消メモ", cancelled_at: Time.current)
    other = Store.create!(name: "非表示店舗")
    StoreCastInvitations::IssueInvitation.call!(store: other, invited_by_user: @admin, note: "他店舗メモ")
    get admin_casts_path(tab: "invitations")
    assert_response :ok
    %w[有効なメモ 期限切れメモ 承認済みメモ].each { |note| assert_includes response.body, note }
    %w[取消メモ 他店舗メモ].each { |note| refute_includes response.body, note }
    refute_includes response.body, active.issued_url
    assert_select "main form", count: 0
  end

  test "new flow reaches dashboard progress without legacy invitation page" do
    post admin_current_store_path, params: { store_id: @store.id }
    issue
    post shared_admin_cast_invitation_path(StoreCastInvitation.last), as: :json
    assert_equal "go_dashboard_for_drinks", @store.reload.onboarding_step
    get dashboard_path
    assert_equal "setup_drinks", @store.reload.onboarding_step
    post skip_admin_onboarding_path
    assert_equal "skipped", @store.reload.onboarding_step
    issue
    post shared_admin_cast_invitation_path(StoreCastInvitation.last), as: :json
    assert_equal "skipped", @store.reload.onboarding_step
  end

  test "expired and cancelled share notifications do not advance onboarding" do
    issue
    invitation = StoreCastInvitation.last
    invitation.update!(expires_at: 1.minute.ago)
    post shared_admin_cast_invitation_path(invitation), as: :json
    assert_response :conflict
    invitation.update!(expires_at: 1.week.from_now, cancelled_at: Time.current)
    post shared_admin_cast_invitation_path(invitation), as: :json
    assert_response :conflict
    assert_equal "create_invite", @store.reload.onboarding_step
  end

  test "skip is bound to the displayed store and rejects unrelated stores" do
    other = Store.create!(name: "別店舗", onboarding_step: :invite_cast)
    StoreMembership.create!(store: other, user: @admin, membership_role: :admin)
    post admin_current_store_path, params: { store_id: other.id }
    post skip_admin_onboarding_path, params: { store_id: @store.id }, as: :json
    assert_response :ok
    assert_equal "skipped", @store.reload.onboarding_step
    assert_equal "invite_cast", other.reload.onboarding_step
    unrelated = Store.create!(name: "無関係", onboarding_step: :invite_cast)
    post skip_admin_onboarding_path, params: { store_id: unrelated.id }, as: :json
    assert_response :forbidden
    assert_equal "invite_cast", unrelated.reload.onboarding_step
  end

  private

  def issue(key: SecureRandom.uuid)
    post admin_cast_invitations_path, params: { store_id: @store.id, request_key: key }, as: :json
    assert_response :ok
  end
end
