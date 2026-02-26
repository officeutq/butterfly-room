# frozen_string_literal: true

require "test_helper"

class AdminBoothsIndexTest < ActionDispatch::IntegrationTest
  setup do
    @store1 = Store.create!(name: "store1")
    @store2 = Store.create!(name: "store2")

    @store_admin  = User.create!(email: "admin@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "sys@example.com", password: "password", role: :system_admin)

    StoreMembership.create!(store: @store1, user: @store_admin, membership_role: :admin)

    @booth1_active = Booth.create!(store: @store1, name: "booth1", status: :offline)
    @booth1_arch   = Booth.create!(store: @store1, name: "booth1_arch", status: :offline, archived_at: Time.current)

    @booth2_active = Booth.create!(store: @store2, name: "booth2", status: :offline)
    @booth2_arch   = Booth.create!(store: @store2, name: "booth2_arch", status: :offline, archived_at: Time.current)
  end

  test "store_admin: index shows only current_store booths (active only by default) and booth name links to enter in modal" do
    sign_in @store_admin, scope: :user

    # store_admin は BaseController#current_store が「最初の admin membership」をfallbackする仕様
    get admin_booths_path
    assert_response :success

    # current_store(store1) の active のみ
    assert_select "tbody tr", minimum: 1
    assert_select "a[href=?][data-turbo-frame=?]", enter_booth_path(@booth1_active), "modal", text: @booth1_active.name
    assert_select "a", text: @booth1_arch.name, count: 0

    # 他storeは出ない
    assert_select "a", text: @booth2_active.name, count: 0
    assert_select "a", text: @booth2_arch.name, count: 0

    # 「詳細」ボタンが無い
    assert_select "a", text: "詳細", count: 0
    assert_select "a[href=?]", admin_booth_path(@booth1_active), count: 0
  end

  test "store_admin: archived=1 includes archived booths in current_store scope" do
    sign_in @store_admin, scope: :user

    get admin_booths_path(archived: 1)
    assert_response :success

    # current_store(store1) の active + archived が出る
    assert_select "a", text: @booth1_active.name, count: 1
    assert_select "a", text: @booth1_arch.name, count: 1

    # 他storeは出ない
    assert_select "a", text: @booth2_active.name, count: 0
    assert_select "a", text: @booth2_arch.name, count: 0
  end

  test "system_admin: index requires current_store and shows only that store booths" do
    sign_in @system_admin, scope: :user

    # current_store 未選択は /admin/stores へ誘導
    get admin_booths_path
    assert_response :redirect
    assert_redirected_to admin_stores_path

    # 選択（選択後は root にリダイレクト）
    post admin_current_store_path, params: { store_id: @store1.id }
    assert_response :redirect
    assert_redirected_to root_path

    # 選択後に index
    get admin_booths_path
    assert_response :success

    # store1 の active のみ
    assert_select "a", text: @booth1_active.name, count: 1
    assert_select "a", text: @booth1_arch.name, count: 0

    # 他storeは出ない
    assert_select "a", text: @booth2_active.name, count: 0
    assert_select "a", text: @booth2_arch.name, count: 0

    # ブース名は enter（modal）
    assert_select "a[href=?][data-turbo-frame=?]", enter_booth_path(@booth1_active), "modal", text: @booth1_active.name

    # 「詳細」ボタンが無い
    assert_select "a", text: "詳細", count: 0
  end

  test "system_admin: archived=1 includes archived booths in current_store scope" do
    sign_in @system_admin, scope: :user

    post admin_current_store_path, params: { store_id: @store1.id }
    assert_response :redirect
    assert_redirected_to root_path

    get admin_booths_path(archived: 1)
    assert_response :success

    assert_select "a", text: @booth1_active.name, count: 1
    assert_select "a", text: @booth1_arch.name, count: 1
    assert_select "a", text: @booth2_active.name, count: 0
    assert_select "a", text: @booth2_arch.name, count: 0
  end
end
