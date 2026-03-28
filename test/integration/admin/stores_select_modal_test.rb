# frozen_string_literal: true

require "test_helper"

class Admin::StoresSelectModalTest < ActionDispatch::IntegrationTest
  def create_store!(name:)
    Store.create!(name: name)
  end

  def create_admin!(stores:)
    user = User.create!(email: "admin_#{SecureRandom.hex}@example.com", password: "password", role: :store_admin)
    stores.each do |s|
      StoreMembership.create!(store: s, user: user, membership_role: :admin)
    end
    user
  end

  test "2件以上: turbo_frame で modal 表示" do
    s1 = create_store!(name: "s1")
    s2 = create_store!(name: "s2")
    admin = create_admin!(stores: [ s1, s2 ])

    sign_in admin, scope: :user

    get select_modal_admin_stores_path, headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_includes response.body, "店舗"
  end

  test "1件: 自動選択されて redirect" do
    s1 = create_store!(name: "s1")
    admin = create_admin!(stores: [ s1 ])

    sign_in admin, scope: :user

    get select_modal_admin_stores_path

    assert_response :redirect
    assert_equal s1.id, @request.session[:current_store_id]
    assert_nil @request.session[:current_booth_id]
  end

  test "0件: modal 表示" do
    admin = User.create!(email: "admin_zero@example.com", password: "password", role: :store_admin)

    sign_in admin, scope: :user

    get select_modal_admin_stores_path, headers: { "Turbo-Frame" => "modal" }

    assert_response :success
  end
end
