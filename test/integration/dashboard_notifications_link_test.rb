# frozen_string_literal: true

require "test_helper"

class DashboardNotificationsLinkTest < ActionDispatch::IntegrationTest
  setup do
    @customer = User.create!(email: "dashboard_notice_customer@example.com", password: "password", role: :customer)
    @cast = User.create!(email: "dashboard_notice_cast@example.com", password: "password", role: :cast)
    @store_admin = User.create!(email: "dashboard_notice_store_admin@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "dashboard_notice_system_admin@example.com", password: "password", role: :system_admin)
  end

  test "system_admin dashboard links to notification management" do
    sign_in @system_admin, scope: :user

    get dashboard_path

    assert_response :success
    assert_select "a[href=?]", system_admin_notifications_path, text: /お知らせ管理/
  end

  test "non system_admin dashboards do not link to notification management" do
    [ @customer, @cast, @store_admin ].each do |user|
      sign_in user, scope: :user

      get dashboard_path

      assert_response :success
      assert_select "a[href=?]", system_admin_notifications_path, count: 0
      assert_no_match "お知らせ管理", response.body

      sign_out :user
    end
  end
end
