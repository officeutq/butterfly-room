# frozen_string_literal: true

require "test_helper"

class BoothEditAuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    @store1 = Store.create!(name: "store1")
    @store2 = Store.create!(name: "store2")

    @booth1 = Booth.create!(store: @store1, name: "booth1", status: :offline)
    @booth2 = Booth.create!(store: @store2, name: "booth2", status: :offline)

    @customer     = User.create!(email: "customer@example.com", password: "password", role: :customer)
    @cast         = User.create!(email: "cast@example.com", password: "password", role: :cast)
    @store_admin  = User.create!(email: "admin@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "sys@example.com", password: "password", role: :system_admin)

    # cast は booth1 に所属
    BoothCast.create!(booth: @booth1, cast_user: @cast)

    # store_admin は store1 の admin
    StoreMembership.create!(store: @store1, user: @store_admin, membership_role: :admin)
  end

  test "customer cannot edit/update (403)" do
    sign_in @customer, scope: :user

    get edit_cast_booth_path(@booth1)
    assert_response :forbidden

    patch cast_booth_path(@booth1), params: { booth: { name: "x" } }
    assert_response :forbidden

    patch admin_booth_path(@booth1), params: { booth: { name: "x" } }
    assert_response :forbidden
  end

  test "cast can edit only own booth" do
    sign_in @cast, scope: :user

    get edit_cast_booth_path(@booth1)
    assert_response :success

    get edit_cast_booth_path(@booth2)
    assert_response :forbidden
  end

  test "store_admin can update only own store booth" do
    sign_in @store_admin, scope: :user

    patch admin_booth_path(@booth1), params: { booth: { name: "x" } }
    assert_response :redirect
    assert_redirected_to admin_booth_path(@booth1)

    patch admin_booth_path(@booth2), params: { booth: { name: "x" } }
    assert_response :not_found
  end

  test "system_admin can update any booth" do
    sign_in @system_admin, scope: :user

    # #206: admin配下は current_store 必須なので、先に選択する
    post admin_current_store_path, params: { store_id: @store1.id }
    assert_response :redirect
    assert_redirected_to dashboard_path

    patch admin_booth_path(@booth1), params: { booth: { name: "x" } }
    assert_response :redirect
    assert_redirected_to admin_booth_path(@booth1)

    patch admin_booth_path(@booth2), params: { booth: { name: "x" } }
    assert_response :redirect
    assert_redirected_to admin_booth_path(@booth2)
  end
end
