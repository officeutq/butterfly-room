# frozen_string_literal: true

require "test_helper"

class AdminSalesReportTest < ActionDispatch::IntegrationTest
  ZONE = "Asia/Tokyo"

  setup do
    @store = Store.create!(name: "sales report admin store")
    @other_store = Store.create!(name: "sales report hidden store")
    @store_admin = User.create!(email: "admin-sales-report@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "system-admin-sales-report@example.com", password: "password", role: :system_admin)
    @customer = User.create!(email: "admin-sales-report-customer@example.com", password: "password", role: :customer)
    @cast = User.create!(email: "admin-sales-report-cast@example.com", password: "password", role: :cast)

    StoreMembership.create!(store: @store, user: @store_admin, membership_role: :admin)

    @booth_a = Booth.create!(store: @store, name: "月次Aブース", status: :offline)
    @booth_b = Booth.create!(store: @store, name: "月次Bブース", status: :offline, archived_at: Time.current)
    @other_booth = Booth.create!(store: @other_store, name: "非表示ブース", status: :offline)
  end

  test "store_admin can view current_store sales report" do
    Time.use_zone(ZONE) do
      period_from = Time.zone.local(2026, 3, 1, 0, 0, 0)

      create_sales!(store: @store, booth: @booth_a, points: 1_000, occurred_at: period_from)
      create_sales!(store: @store, booth: @booth_b, points: 2_000, occurred_at: period_from + 1.day)
      create_sales!(store: @other_store, booth: @other_booth, points: 9_999, occurred_at: period_from + 2.days)
      create_order_without_ledger!(store: @store, booth: @booth_a, points: 7_777, status: :pending, occurred_at: period_from + 3.days)
      create_order_without_ledger!(store: @store, booth: @booth_a, points: 6_666, status: :refunded, occurred_at: period_from + 4.days)
    end

    sign_in @store_admin, scope: :user
    select_current_store(@store)

    get admin_sales_path(month: "2026-03")
    assert_response :success

    body = response.body
    assert_select "h1", text: "売上レポート"
    assert_select "form[action=?]", admin_sales_path
    assert_includes body, "消化確定ベースの売上レポート（gross）"
    assert_includes body, "3,000 pt"
    assert_includes body, @booth_a.name
    assert_includes body, @booth_b.name
    refute_includes body, @other_booth.name
    refute_includes body, "9,999 pt"
    refute_includes body, "7,777 pt"
    refute_includes body, "6,666 pt"

    assert_equal 1, body.scan("支払予定額").size
    forbidden_words = %w[残高 引出 出金 受取可能 預かり いつでも受け取れる あなたの取り分 振込額]
    forbidden_words.each { |word| refute_includes body, word }

    refute_includes body, "配信時間"
    refute_includes body, "売上/時間"
    refute_includes body, "配信者別数値"
  end

  test "store_admin without current_store falls back to own membership" do
    sign_in @store_admin, scope: :user

    get admin_sales_path

    assert_response :success
    assert_select "h1", text: "売上レポート"
  end

  test "system_admin can view selected current_store sales report" do
    Time.use_zone(ZONE) do
      create_sales!(
        store: @other_store,
        booth: @other_booth,
        points: 4_000,
        occurred_at: Time.zone.local(2026, 3, 10, 12, 0, 0)
      )
    end

    sign_in @system_admin, scope: :user
    select_current_store(@other_store)

    get admin_sales_path(month: "2026-03")

    assert_response :success
    assert_includes response.body, @other_booth.name
    assert_includes response.body, "4,000 pt"
  end

  test "customer cannot view admin sales report" do
    sign_in @customer, scope: :user

    get admin_sales_path

    assert_response :forbidden
  end

  private

  def select_current_store(store)
    post admin_current_store_path, params: { store_id: store.id }
    follow_redirect!
    assert_response :success
  end

  def create_sales!(store:, booth:, points:, occurred_at:)
    stream_session = create_stream_session!(store:, booth:, occurred_at:)
    drink_item = create_drink_item!(store:, points:)
    drink_order =
      DrinkOrder.create!(
        store: store,
        booth: booth,
        stream_session: stream_session,
        customer_user: @customer,
        drink_item: drink_item,
        status: :consumed,
        consumed_at: occurred_at
      )

    StoreLedgerEntry.create!(
      store: store,
      stream_session: stream_session,
      drink_order: drink_order,
      points: points,
      occurred_at: occurred_at
    )
  end

  def create_order_without_ledger!(store:, booth:, points:, status:, occurred_at:)
    stream_session = create_stream_session!(store:, booth:, occurred_at:)
    drink_item = create_drink_item!(store:, points:)

    DrinkOrder.create!(
      store: store,
      booth: booth,
      stream_session: stream_session,
      customer_user: @customer,
      drink_item: drink_item,
      status: status,
      refunded_at: (status == :refunded ? occurred_at : nil)
    )
  end

  def create_stream_session!(store:, booth:, occurred_at:)
    StreamSession.create!(
      store: store,
      booth: booth,
      started_by_cast_user: @cast,
      status: :ended,
      started_at: occurred_at - 1.hour,
      broadcast_started_at: occurred_at - 1.hour,
      ended_at: occurred_at
    )
  end

  def create_drink_item!(store:, points:)
    DrinkItem.create!(
      store: store,
      name: "管理売上レポート用ドリンク#{points}",
      price_points: points,
      enabled: true
    )
  end
end
