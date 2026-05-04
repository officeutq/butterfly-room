# frozen_string_literal: true

require "test_helper"

class CastMetricsQueryTest < ActiveSupport::TestCase
  setup do
    @store = Store.create!(name: "metrics store")

    @cast_with_sales = User.create!(
      email: "cast_with_sales@example.com",
      password: "password",
      role: :cast,
      display_name: "売上ありキャスト"
    )

    @cast_with_stream_only = User.create!(
      email: "cast_with_stream_only@example.com",
      password: "password",
      role: :cast,
      display_name: "配信のみキャスト"
    )

    @cast_without_metrics = User.create!(
      email: "cast_without_metrics@example.com",
      password: "password",
      role: :cast,
      display_name: "実績なしキャスト"
    )

    @customer = User.create!(
      email: "metrics_customer@example.com",
      password: "password",
      role: :customer
    )

    @booth_sales = StoreBoothFactory.create!(store: @store, name: "売上ブース", cast_user: @cast_with_sales)
    @booth_stream = StoreBoothFactory.create!(store: @store, name: "配信ブース", cast_user: @cast_with_stream_only)
    @booth_empty = StoreBoothFactory.create!(store: @store, name: "実績なしブース", cast_user: @cast_without_metrics)

    @from = Time.zone.local(2026, 4, 1, 0, 0, 0)
    @to = Time.zone.local(2026, 5, 1, 0, 0, 0)
  end

  test "returns only casts with sales or broadcast seconds by default" do
    create_consumed_sales!(
      booth: @booth_sales,
      cast_user: @cast_with_sales,
      points: 1_001,
      occurred_at: @from + 1.day
    )

    create_stream_session!(
      booth: @booth_stream,
      cast_user: @cast_with_stream_only,
      broadcast_started_at: @from + 2.days,
      ended_at: @from + 2.days + 30.minutes
    )

    rows = CastMetricsQuery.new(store: @store, from: @from, to: @to).call

    assert_equal [ @cast_with_sales.id, @cast_with_stream_only.id ], rows.map { |r| r.cast_user.id }
    assert_equal 1_001, rows.first.stream_sales_points
    assert_equal 700, rows.first.real_store_sales_yen
  end

  test "includes casts without metrics when include_all_casts is true" do
    create_consumed_sales!(
      booth: @booth_sales,
      cast_user: @cast_with_sales,
      points: 1_000,
      occurred_at: @from + 1.day
    )

    rows =
      CastMetricsQuery.new(
        store: @store,
        from: @from,
        to: @to,
        include_all_casts: true
      ).call

    assert_equal 3, rows.size
    assert_includes rows.map { |r| r.cast_user.id }, @cast_without_metrics.id
  end

  test "uses broadcast_started_at for stream seconds" do
    create_stream_session!(
      booth: @booth_stream,
      cast_user: @cast_with_stream_only,
      started_at: @from + 1.hour,
      broadcast_started_at: @from + 2.hours,
      ended_at: @from + 3.hours
    )

    row = CastMetricsQuery.new(store: @store, from: @from, to: @to).call.first

    assert_equal @cast_with_stream_only.id, row.cast_user.id
    assert_equal 3600, row.stream_seconds
  end

  test "clips broadcast seconds to selected period" do
    create_stream_session!(
      booth: @booth_stream,
      cast_user: @cast_with_stream_only,
      broadcast_started_at: @from - 30.minutes,
      ended_at: @from + 30.minutes
    )

    row = CastMetricsQuery.new(store: @store, from: @from, to: @to).call.first

    assert_equal 1800, row.stream_seconds
  end

  test "orders rows by stream sales desc" do
    create_consumed_sales!(
      booth: @booth_sales,
      cast_user: @cast_with_sales,
      points: 2_000,
      occurred_at: @from + 1.day
    )

    create_consumed_sales!(
      booth: @booth_stream,
      cast_user: @cast_with_stream_only,
      points: 5_000,
      occurred_at: @from + 1.day
    )

    rows = CastMetricsQuery.new(store: @store, from: @from, to: @to).call

    assert_equal [ @cast_with_stream_only.id, @cast_with_sales.id ], rows.map { |r| r.cast_user.id }
  end

  private

  def create_stream_session!(booth:, cast_user:, started_at: nil, broadcast_started_at:, ended_at:)
    StreamSession.create!(
      store: @store,
      booth: booth,
      started_by_cast_user: cast_user,
      status: :ended,
      started_at: started_at || broadcast_started_at,
      broadcast_started_at: broadcast_started_at,
      ended_at: ended_at
    )
  end

  def create_consumed_sales!(booth:, cast_user:, points:, occurred_at:)
    session =
      create_stream_session!(
        booth: booth,
        cast_user: cast_user,
        broadcast_started_at: occurred_at - 1.hour,
        ended_at: occurred_at
      )

    drink_item =
      DrinkItem.create!(
        store: @store,
        name: "ドリンク#{points}",
        price_points: points,
        enabled: true
      )

    drink_order =
      DrinkOrder.create!(
        store: @store,
        booth: booth,
        stream_session: session,
        customer_user: @customer,
        drink_item: drink_item,
        status: :consumed,
        consumed_at: occurred_at
      )

    StoreLedgerEntry.create!(
      store: @store,
      stream_session: session,
      drink_order: drink_order,
      points: points,
      occurred_at: occurred_at
    )
  end

  class StoreBoothFactory
    def self.create!(store:, name:, cast_user:)
      booth = Booth.create!(store: store, name: name, status: :offline)
      BoothCast.create!(booth: booth, cast_user: cast_user)
      booth
    end
  end
end
