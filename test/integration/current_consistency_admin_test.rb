# frozen_string_literal: true

require "test_helper"

class CurrentConsistencyAdminTest < ActionDispatch::IntegrationTest
  def create_store!(name:)
    Store.create!(name: name)
  end

  def create_booth!(store:, name: "booth", status: :offline)
    Booth.create!(store: store, name: name, status: status, ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/#{SecureRandom.hex(4)}")
  end

  test "booth優先: cast/current_booth 後は store 不一致のままでも admin_root で補正される" do
    store1 = create_store!(name: "Store 1")
    store2 = create_store!(name: "Store 2")

    booth1 = create_booth!(store: store1, name: "Booth 1", status: :standby)
    booth2 = create_booth!(store: store2, name: "Booth 2", status: :offline)

    admin = User.create!(email: "admin_reconcile@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: store1, user: admin, membership_role: :admin)
    StoreMembership.create!(store: store2, user: admin, membership_role: :admin)

    sign_in admin, scope: :user

    post enter_as_cast_booth_path(booth1)
    assert_response :redirect
    assert_equal booth1.id, @request.session[:current_booth_id]
    assert_equal store1.id, @request.session[:current_store_id]

    post cast_current_booth_path, params: { booth_id: booth2.id }
    assert_response :redirect
    assert_equal booth2.id, @request.session[:current_booth_id]
    assert_equal store1.id, @request.session[:current_store_id]

    get admin_booths_path
    assert_response :success

    assert_equal store2.id, @request.session[:current_store_id]
    assert_includes response.body, "store:"
    assert_includes response.body, store2.name
    assert_includes response.body, "booth:"
    assert_includes response.body, booth2.name
  end

  test "boothが無効（record不存在）なら current_booth_id はクリアされる" do
    store = create_store!(name: "Store")
    booth = create_booth!(store: store, name: "Booth", status: :standby)

    admin = User.create!(email: "admin_missing_booth@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: store, user: admin, membership_role: :admin)

    sign_in admin, scope: :user

    post enter_as_cast_booth_path(booth)
    assert_response :redirect
    assert_equal booth.id, @request.session[:current_booth_id]
    assert_equal store.id, @request.session[:current_store_id]

    booth.update_column(:current_stream_session_id, nil)
    StreamSession.where(booth_id: booth.id).delete_all
    Booth.delete(booth.id)

    get admin_booths_path
    assert_response :success

    assert_nil @request.session[:current_booth_id]
    assert_equal store.id, @request.session[:current_store_id]
    assert_includes response.body, store.name
  end

  test "boothが無効（権限的に無効）なら current_booth_id はクリアされる" do
    store1 = create_store!(name: "Store 1")
    store2 = create_store!(name: "Store 2")

    booth1 = create_booth!(store: store1, name: "Booth 1", status: :standby)
    booth2 = create_booth!(store: store2, name: "Booth 2", status: :offline)

    admin = User.create!(email: "admin_unauthorized_booth@example.com", password: "password", role: :store_admin)

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
    assert_equal store1.id, @request.session[:current_store_id]

    StoreMembership.delete(m2.id)

    get admin_booths_path
    assert_response :success

    assert_nil @request.session[:current_booth_id]
    assert_equal store1.id, @request.session[:current_store_id]
    assert_includes response.body, store1.name
  end
end
