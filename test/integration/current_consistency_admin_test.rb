# frozen_string_literal: true

require "test_helper"

class CurrentConsistencyAdminTest < ActionDispatch::IntegrationTest
  def create_store!(name:)
    Store.create!(name: name)
  end

  def create_booth!(store:, name: "booth", status: :offline)
    Booth.create!(store: store, name: name, status: status)
  end

  test "booth優先: sessionのstore不一致は補正される（admin_rootで補正）" do
    store1 = create_store!(name: "Store 1")
    store2 = create_store!(name: "Store 2")

    booth1 = create_booth!(store: store1, name: "Booth 1", status: :standby)
    booth2 = create_booth!(store: store2, name: "Booth 2", status: :offline)

    admin = User.create!(email: "admin_reconcile@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: store1, user: admin, membership_role: :admin)
    StoreMembership.create!(store: store2, user: admin, membership_role: :admin)

    sign_in admin, scope: :user

    # まず booth1 で current_booth_id/current_store_id をセット
    post enter_as_cast_booth_path(booth1)
    assert_response :redirect
    assert_equal booth1.id, @request.session[:current_booth_id]
    assert_equal store1.id, @request.session[:current_store_id]

    # 次に cast/current_booth で booth2 を選ぶ（store_id は更新されないので不一致が起きる）
    post cast_current_booth_path, params: { booth_id: booth2.id }
    assert_response :redirect
    assert_equal booth2.id, @request.session[:current_booth_id]
    assert_equal store1.id, @request.session[:current_store_id], "store_id は古いまま（不一致）"

    # admin_root で current_store が解決されるタイミングで、store が booth2.store に補正される
    get admin_root_path
    assert_response :success

    assert_equal store2.id, @request.session[:current_store_id], "booth優先で store_id が補正される"
    assert_includes response.body, "現在の店舗:"
    assert_includes response.body, store2.name
  end

  test "boothが無効（record不存在）なら current_booth_id はクリアされる" do
    store = create_store!(name: "Store")
    booth = create_booth!(store: store, name: "Booth", status: :standby)

    admin = User.create!(email: "admin_missing_booth@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: store, user: admin, membership_role: :admin)

    sign_in admin, scope: :user

    # session をセット
    post enter_as_cast_booth_path(booth)
    assert_response :redirect
    assert_equal booth.id, @request.session[:current_booth_id]
    assert_equal store.id, @request.session[:current_store_id]

    # booth を消して record不存在状態を作る（依存があるので delete で）
    Booth.delete(booth.id)

    # admin_root で補正（booth不存在なので current_booth_id はクリアされる）
    get admin_root_path
    assert_response :success

    assert_nil @request.session[:current_booth_id]
    assert_equal store.id, @request.session[:current_store_id], "store は session/store で維持される"
    assert_includes response.body, store.name
  end

  test "boothが無効（権限的に無効）なら current_booth_id はクリアされる" do
    store1 = create_store!(name: "Store 1")
    store2 = create_store!(name: "Store 2")

    booth1 = create_booth!(store: store1, name: "Booth 1", status: :standby)
    booth2 = create_booth!(store: store2, name: "Booth 2", status: :offline)

    admin = User.create!(email: "admin_unauthorized_booth@example.com", password: "password", role: :store_admin)

    # 両方 membership を付けて booth2 を選べる状態にしてから…
    StoreMembership.create!(store: store1, user: admin, membership_role: :admin)
    m2 = StoreMembership.create!(store: store2, user: admin, membership_role: :admin)

    sign_in admin, scope: :user

    post enter_as_cast_booth_path(booth1)
    assert_response :redirect
    assert_equal booth1.id, @request.session[:current_booth_id]
    assert_equal store1.id, @request.session[:current_store_id]

    post cast_current_booth_path, params: { booth_id: booth2.id }
    assert_response :redirect
    assert_equal booth2.id, @request.session[:current_booth_id]

    # membership を消して「権限的に無効（脱退）」を再現
    StoreMembership.delete(m2.id)

    get admin_root_path
    assert_response :success

    assert_nil @request.session[:current_booth_id], "権限的に無効なら booth はクリアされる"
    # store は booth優先できないので session store（または fallback）へ
    assert_equal store1.id, @request.session[:current_store_id]
    assert_includes response.body, store1.name
  end
end
