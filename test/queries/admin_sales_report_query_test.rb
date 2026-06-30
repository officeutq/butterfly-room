# frozen_string_literal: true

require "test_helper"

class AdminSalesReportQueryTest < ActiveSupport::TestCase
  ZONE = "Asia/Tokyo"

  setup do
    @store = Store.create!(name: "sales report store")
    @other_store = Store.create!(name: "sales report other store")
    @cast = User.create!(email: "sales-report-cast@example.com", password: "password", role: :cast)
    @customer = User.create!(email: "sales-report-customer@example.com", password: "password", role: :customer)

    @booth_a = Booth.create!(store: @store, name: "Aブース", status: :offline)
    @booth_b = Booth.create!(store: @store, name: "Bブース", status: :offline, archived_at: Time.current)
    @other_booth = Booth.create!(store: @other_store, name: "他店舗ブース", status: :offline)
  end

  test "aggregates monthly total daily rows and booth rows by occurred_at in JST" do
    Time.use_zone(ZONE) do
      period_from = Time.zone.local(2026, 3, 1, 0, 0, 0)
      period_to = Time.zone.local(2026, 4, 1, 0, 0, 0)

      create_sales!(store: @store, booth: @booth_a, points: 100, occurred_at: period_from)
      create_sales!(store: @store, booth: @booth_b, points: 200, occurred_at: period_to - 1.second)

      create_sales!(store: @store, booth: @booth_a, points: 9_999, occurred_at: period_to)
      create_sales!(store: @other_store, booth: @other_booth, points: 8_888, occurred_at: period_from + 1.day)
      create_order_without_ledger!(store: @store, booth: @booth_a, points: 7_777, status: :pending, occurred_at: period_from + 2.days)
      create_order_without_ledger!(store: @store, booth: @booth_a, points: 6_666, status: :refunded, occurred_at: period_from + 3.days)

      report = AdminSalesReportQuery.new(store: @store, from: period_from, to: period_to).call

      assert_equal 300, report.month_total_points
      assert_equal 31, report.daily_rows.size
      assert_equal 100, report.daily_rows.find { |row| row.date == Date.new(2026, 3, 1) }.points
      assert_equal 200, report.daily_rows.find { |row| row.date == Date.new(2026, 3, 31) }.points

      assert_equal [ @booth_b.id, @booth_a.id ], report.booth_rows.map(&:booth_id)
      assert_equal [ 200, 100 ], report.booth_rows.map(&:points)
    end
  end

  private

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
      consumed_at: (status == :consumed ? occurred_at : nil),
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
      name: "売上レポート用ドリンク#{points}",
      price_points: points,
      enabled: true
    )
  end
end
