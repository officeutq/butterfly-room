# frozen_string_literal: true

require "test_helper"

class SystemAdminLogsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email: "logs-viewer@example.com", password: "password", role: :system_admin, display_name: "運営担当")
    @request_id = SecureRandom.uuid
    @store = Store.create!(name: "変更前")
    Stores::UpdateService.new(store: @store, attributes: { name: "<script>alert(1)</script>", description: "secret-description" },
      actor_user: @admin, source: "web", request_id: @request_id).call
    @change = ChangeLog.where(request_id: @request_id).sole
    @error = Logs::RecordErrorService.call(error: RuntimeError.new("secret-error"), handled: true, source: "job",
      context: { request_id: @request_id, actor_user_id: @admin.id, store_id: @store.id, job_class: "ExampleJob", job_id: "job-123", executions: 2 })
  end

  teardown do
    ErrorLog.where(request_id: @request_id).delete_all
  end

  test "only system administrators can read both lists and details" do
    paths = [ system_admin_error_logs_path, system_admin_error_log_path(@error),
      system_admin_change_logs_path, system_admin_change_log_path(@change) ]
    paths.each do |path|
      get path
      assert_response :redirect
    end
    %i[customer cast store_admin].each do |role|
      user = User.create!(email: "logs-#{role}@example.com", password: "password", role: role)
      sign_in user, scope: :user
      paths.each do |path|
        get path
        assert_response :forbidden
      end
      sign_out user
    end
    sign_in @admin, scope: :user
    paths.each do |path|
      get path
      assert_response :success
    end
  end

  test "actual service changes are searchable and details escape values and hide private data" do
    sign_in @admin, scope: :user
    get system_admin_change_logs_path, params: { request_id: @request_id, actor_user_id: @admin.id,
      store_id: @store.id, target_type: "Store", target_id: @store.id, change_action: "updated", source: "web" }
    assert_response :success
    assert_select "a[href=?]", system_admin_change_log_path(@change), count: 1
    assert_select "td", text: /運営担当/
    assert_no_match(/secret-description|alert\(1\)/, response.body)

    get system_admin_change_log_path(@change)
    assert_response :success
    assert_select "td", text: "<script>alert(1)</script>"
    assert_select "script", text: /alert\(1\)/, count: 0
    assert_select "td", text: "秘匿（変更の事実のみ記録）"
    assert_not_includes response.body, "secret-description"
    assert_select "main form", count: 0
  end

  test "errors are filtered with exact values and safely displayed" do
    sign_in @admin, scope: :user
    get system_admin_error_logs_path, params: { request_id: @request_id, severity: "error", source: "job", exception_class: "RuntimeError" }
    assert_response :success
    assert_select "a[href=?]", system_admin_error_log_path(@error)
    get system_admin_error_logs_path, params: { request_id: @request_id, severity: "warning" }
    assert_select "a[href=?]", system_admin_error_log_path(@error), count: 0
    get system_admin_error_log_path(@error)
    assert_response :success
    assert_includes response.body, "ExampleJob"
    assert_includes response.body, "job-123"
    assert_includes response.body, "復旧済みとは限りません"
    assert_not_includes response.body, "secret-error"
    assert_select "main" do |content|
      assert_not_includes content.text, @admin.email
    end
  end

  test "invalid search shows a message and no entries" do
    sign_in @admin, scope: :user
    get system_admin_change_logs_path, params: { from: "2025-01-01", to: "2026-09-12" }
    assert_response :success
    assert_select "[role=alert]", text: /366日以内/
    assert_select "tbody tr", count: 0
    get system_admin_change_logs_path, params: { target_type: [ "Store" ] }
    assert_response :success
    assert_select "[role=alert]", text: /1項目につき1つ/
    assert_select "tbody tr", count: 0
    get system_admin_change_logs_path, params: { page: "1001" }
    assert_response :success
    assert_select "[role=alert]", text: /ページ/
  end

  test "archived logs and missing actor identifiers remain readable" do
    ChangeLog.where(id: @change.id).update_all(archived_at: Time.current, actor_user_id: 9_000_000_000)
    sign_in @admin, scope: :user
    get system_admin_change_logs_path, params: { request_id: @request_id }
    assert_select "a[href=?]", system_admin_change_log_path(@change), count: 0
    get system_admin_change_logs_path, params: { request_id: @request_id, archive: "archived" }
    assert_select "a[href=?]", system_admin_change_log_path(@change)
    assert_select "td", text: "ユーザー ID: 9000000000"
    get system_admin_change_log_path(@change)
    assert_response :success
    assert_includes response.body, "9000000000"
  end

  test "log routes expose no editing or deletion and dashboard offers navigation" do
    routes = Rails.application.routes.routes.select { |route| %w[system_admin/error_logs system_admin/change_logs].include?(route.defaults[:controller]) }
    assert_equal 4, routes.size
    assert routes.all? { |route| route.verb == "GET" && %w[index show].include?(route.defaults[:action]) }
    sign_in @admin, scope: :user
    get dashboard_path
    assert_response :success
    assert_select "a[href=?]", system_admin_error_logs_path, text: /システムログ/
  end
end
