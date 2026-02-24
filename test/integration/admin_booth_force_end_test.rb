# frozen_string_literal: true

require "test_helper"

class AdminBoothForceEndTest < ActionDispatch::IntegrationTest
  setup do
    @store1 = Store.create!(name: "store1")
    @store2 = Store.create!(name: "store2")

    @booth1 = Booth.create!(store: @store1, name: "booth1", status: :live)
    @booth2 = Booth.create!(store: @store2, name: "booth2", status: :away)

    @cast = User.create!(email: "cast@example.com", password: "password", role: :cast)

    @store_admin  = User.create!(email: "admin@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "sys@example.com", password: "password", role: :system_admin)

    StoreMembership.create!(store: @store1, user: @store_admin, membership_role: :admin)

    @session1 = StreamSession.create!(
      booth: @booth1,
      store: @store1,
      started_by_cast_user: @cast,
      status: :live,
      started_at: Time.current # ★追加
    )

    @booth1.update!(current_stream_session_id: @session1.id)

    @session2 = StreamSession.create!(
      booth: @booth2,
      store: @store2,
      started_by_cast_user: @cast,
      status: :live,
      started_at: Time.current # ★追加
    )

    @booth2.update!(current_stream_session_id: @session2.id)
  end

  test "store_admin can force_end own store booth" do
    sign_in @store_admin, scope: :user

    post force_end_admin_booth_path(@booth1)
    assert_response :redirect
    assert_redirected_to admin_booth_path(@booth1)

    @booth1.reload
    @session1.reload

    assert @booth1.offline?
    assert_nil @booth1.current_stream_session_id
    assert_equal "ended", @session1.status
    assert @session1.ended_at.present?
  end

  test "store_admin cannot force_end other store booth (404 by scope)" do
    sign_in @store_admin, scope: :user

    post force_end_admin_booth_path(@booth2)
    assert_response :not_found
  end

  test "system_admin can force_end any booth" do
    sign_in @system_admin, scope: :user

    # #206: admin配下は current_store 必須なので、先に選択する
    post admin_current_store_path, params: { store_id: @store1.id }
    assert_response :redirect
    assert_redirected_to root_path

    post force_end_admin_booth_path(@booth2)
    assert_response :redirect
    assert_redirected_to admin_booth_path(@booth2)

    @booth2.reload
    @session2.reload

    assert @booth2.offline?
    assert_nil @booth2.current_stream_session_id
    assert_equal "ended", @session2.status
    assert @session2.ended_at.present?
  end

  test "cast cannot access admin force_end (403)" do
    sign_in @cast, scope: :user

    post force_end_admin_booth_path(@booth1)
    assert_response :forbidden
  end
end
