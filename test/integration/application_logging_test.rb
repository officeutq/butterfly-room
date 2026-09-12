# frozen_string_literal: true

require "test_helper"

class ApplicationLoggingTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email: "logging-admin@example.com", password: "password", role: :system_admin)
    @store = Store.create!(name: "更新前")
    @request_ids = []
  end

  teardown do
    ErrorLog.where(request_id: @request_ids).delete_all
  end

  test "authorized store update records actor request and actual target" do
    sign_in @admin, scope: :user
    request_id = SecureRandom.uuid
    patch admin_store_path(@store), params: { store: { name: "更新後" }, actor_user_id: 999 }, headers: { "X-Request-ID" => request_id }
    assert_redirected_to dashboard_path
    entry = ChangeLog.where(target_type: "Store", target_id: @store.id).sole
    assert_equal @admin.id, entry.actor_user_id
    assert_equal request_id, entry.request_id
    assert_equal [ "更新前", "更新後" ], entry.change_data["name"]
  end

  test "rejected and invalid changes have no successful history" do
    customer = User.create!(email: "logging-customer@example.com", password: "password", role: :customer)
    sign_in customer, scope: :user
    assert_no_difference "ChangeLog.count" do
      patch admin_store_path(@store), params: { store: { name: "拒否" } }
      assert_response :forbidden
      sign_out customer
      sign_in @admin, scope: :user
      patch admin_store_path(@store), params: { store: { name: "" } }
      assert_redirected_to edit_admin_store_path(@store)
    end
    assert_equal "更新前", @store.reload.name
  end

  test "unhandled web errors are recorded with separate request identities" do
    second = User.create!(email: "logging-second@example.com", password: "password", role: :system_admin)
    original = DashboardController.instance_method(:show)
    DashboardController.define_method(:show) { raise "web-secret" }
    [ @admin, second ].each do |actor|
      sign_in actor, scope: :user
      request_id = SecureRandom.uuid
      @request_ids << request_id
      assert_raises(RuntimeError) { get dashboard_path, headers: { "X-Request-ID" => request_id } }
      entry = ErrorLog.where(request_id:).sole
      assert_equal actor.id, entry.actor_user_id
      assert_equal "web", entry.source
      assert_not entry.handled
      assert_not_includes entry.to_json, "web-secret"
      sign_out actor
    end
  ensure
    DashboardController.define_method(:show, original)
  end
end
