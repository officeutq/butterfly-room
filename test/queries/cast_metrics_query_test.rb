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

    @store_admin_performer = User.create!(
      email: "store_admin_performer@example.com",
      password: "password",
      role: :store_admin,
      display_name: "店舗管理者配信者"
    )

    @system_admin_performer = User.create!(
      email: "system_admin_performer@example.com",
      password: "password",
      role: :system_admin,
      display_name: "システム管理者配信者"
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

  test "includes store_admin performer when they have stream session" do
    create_stream_session!(
      booth: @booth_sales,
      cast_user: @store_admin_performer,
      broadcast_started_at: @from + 3.days,
      ended_at: @from + 3.days + 45.minutes
    )

    rows = CastMetricsQuery.new(store: @store, from: @from, to: @to).call

    assert_equal [ @store_admin_performer.id ], rows.map { |r| r.cast_user.id }
    assert_equal "store_admin", rows.first.cast_user.role
    assert_equal 2700, rows.first.stream_seconds
  end

  test "does not include stream actor without broadcast start when include_all_casts is true" do
    create_stream_session!(
      booth: @booth_sales,
      cast_user: @system_admin_performer,
      started_at: @from + 4.days,
      broadcast_started_at: nil,
      ended_at: @from + 4.days + 5.minutes
    )

    rows =
      CastMetricsQuery.new(
        store: @store,
        from: @from,
        to: @to,
        include_all_casts: true
      ).call

    user_ids = rows.map { |r| r.cast_user.id }

    assert_includes user_ids, @cast_without_metrics.id
    refute_includes user_ids, @system_admin_performer.id
  end

  test "includes past broadcast actor when include_all_casts is true even without selected month metrics" do
    create_stream_session!(
      booth: @booth_sales,
      cast_user: @system_admin_performer,
      broadcast_started_at: @from - 10.days,
      ended_at: @from - 10.days + 10.minutes
    )

    rows =
      CastMetricsQuery.new(
        store: @store,
        from: @from,
        to: @to,
        include_all_casts: true
      ).call

    row = rows.find { |r| r.cast_user.id == @system_admin_performer.id }

    assert_not_nil row
    assert_equal "system_admin", row.cast_user.role
    assert_equal 0, row.stream_sales_points
    assert_equal 0, row.stream_seconds
  end

  test "H03 X準備 Y配信 Z担当の売上と時間をYだけに帰属させ店舗総額を維持する" do
    ledger = create_consumed_sales!(booth: @booth_sales, cast_user: @cast_with_stream_only,
      points: 1_001, occurred_at: @from + 1.day)
    record_publisher(ledger.stream_session, @store_admin_performer)
    before = [ ledger.reload.attributes, ledger.stream_session.reload.attributes ]
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      rows = CastMetricsQuery.new(store: @store, from: @from, to: @to).call
      assert_equal [ @store_admin_performer.id ], rows.map { |row| row.cast_user.id }
      assert_equal 1_001, rows.sole.stream_sales_points
      assert_equal 3600, rows.sole.stream_seconds
      assert_equal 1001.0, rows.sole.sales_per_hour
      assert_equal 700, rows.sole.real_store_sales_yen
      report = AdminSalesReportQuery.new(store: @store, from: @from, to: @to).call
      assert_equal report.month_total_points, rows.sum(&:stream_sales_points)
      assert_equal 1_001, report.booth_rows.sole.points
      assert_equal before, [ ledger.reload.attributes, ledger.stream_session.reload.attributes ]
    end
  end

  test "H04 不明分は金額が大きくても末尾に残し補完済みとの合計が店舗売上と一致する" do
    known = create_consumed_sales!(booth: @booth_sales, cast_user: @cast_with_sales,
      points: 101, occurred_at: @from)
    record_publisher(known.stream_session, @cast_with_sales, source: "legacy_creator_backfill")
    unknown = create_consumed_sales!(booth: @booth_stream, cast_user: @cast_with_stream_only,
      points: 5_001, occurred_at: @from + 1.day)
    create_consumed_sales!(booth: @booth_stream, cast_user: @cast_with_stream_only,
      points: 9_999, occurred_at: @to)
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      rows = CastMetricsQuery.new(store: @store, from: @from, to: @to).call
      assert_equal [ @cast_with_sales.id, nil ], rows.map { |row| row.cast_user&.id }
      assert_equal 5_001, rows.last.stream_sales_points
      # 月初前の既知配信は0秒、月末直前1時間の不明配信も既存期間条件で加算する。
      assert_equal 7200, rows.last.stream_seconds
      assert_equal 3500, rows.last.real_store_sales_yen
      report = AdminSalesReportQuery.new(store: @store, from: @from, to: @to).call
      assert_equal 5_102, rows.sum(&:stream_sales_points)
      assert_equal report.month_total_points, rows.sum(&:stream_sales_points)
      assert_nil unknown.stream_session.reload.actual_publisher_user_id
    end
  end

  test "H03 所属変更・退会後も記録済みの人物を含み同名の管理者を混同しない" do
    @store_admin_performer.update!(display_name: "同じ名前", deleted_at: Time.current)
    @system_admin_performer.update!(display_name: "同じ名前")
    [ @store_admin_performer, @system_admin_performer ].each_with_index do |user, i|
      session = create_stream_session!(booth: @booth_sales, cast_user: @cast_with_sales,
        broadcast_started_at: @from + i.hours, ended_at: @from + i.hours + 30.minutes)
      record_publisher(session, user)
    end
    BoothCast.where(booth: @booth_sales).delete_all
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      rows = CastMetricsQuery.new(store: @store, from: @from, to: @to).call
      assert_equal [ @store_admin_performer.id, @system_admin_performer.id ], rows.map { |row| row.cast_user.id }
      assert_equal [ 1800, 1800 ], rows.map(&:stream_seconds)
      assert_equal [ 0, 0 ], rows.map(&:stream_sales_points)
      assert rows.first.cast_user.deleted?
    end
  end

  test "H03 月をまたぐ配信中と終了済みの時間を既存の範囲で切り詰める" do
    first = create_stream_session!(booth: @booth_sales, cast_user: @cast_with_sales,
      broadcast_started_at: @from - 30.minutes, ended_at: @from + 30.minutes)
    record_publisher(first, @store_admin_performer)
    current = create_stream_session!(booth: @booth_stream, cast_user: @cast_with_stream_only,
      broadcast_started_at: @from + 1.hour, ended_at: nil)
    current.update!(status: :live)
    record_publisher(current, @store_admin_performer)
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      row = CastMetricsQuery.new(store: @store, from: @from, to: @to, now: @from + 2.hours).call.sole
      assert_equal 5400, row.stream_seconds
      current.update!(status: :ended, ended_at: @from + 2.hours)
      assert_equal row.to_h, CastMetricsQuery.new(store: @store, from: @from, to: @to, now: @from + 3.hours).call.sole.to_h
    end
  end

  test "H03 全員表示は担当者と過去の実配信者を含み準備作成だけの人物を足さない" do
    old = create_stream_session!(booth: @booth_sales, cast_user: @system_admin_performer,
      broadcast_started_at: @from - 10.days, ended_at: @from - 9.days)
    record_publisher(old, @store_admin_performer)
    create_stream_session!(booth: @booth_sales, cast_user: @system_admin_performer,
      started_at: @from, broadcast_started_at: nil, ended_at: @from + 1.hour)
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      assert_empty CastMetricsQuery.new(store: @store, from: @from, to: @to).call
      rows = CastMetricsQuery.new(store: @store, from: @from, to: @to, include_all_casts: true).call
      assert_equal 4, rows.size
      assert_includes rows.map { |row| row.cast_user.id }, @store_admin_performer.id
      refute_includes rows.map { |row| row.cast_user.id }, @system_admin_performer.id
      assert_equal 0, rows.sum(&:stream_seconds)
    end
  end

  test "H03 同じ実配信者の別店舗の実績を混ぜず未消化・返却の金額を含めない" do
    here = create_consumed_sales!(booth: @booth_sales, cast_user: @cast_with_sales,
      points: 100, occurred_at: @from + 1.day)
    record_publisher(here.stream_session, @store_admin_performer)
    other_store = Store.create!(name: "Other metrics store")
    other_booth = Booth.create!(store: other_store, name: "Other metrics booth")
    other = StreamSession.create!(store: other_store, booth: other_booth, started_by_cast_user: @cast_with_sales,
      status: :ended, started_at: @from, broadcast_started_at: @from, ended_at: @from + 5.hours)
    record_publisher(other, @store_admin_performer)
    %i[pending refunded].each do |status|
      DrinkOrder.create!(store: @store, booth: @booth_sales, stream_session: here.stream_session,
        customer_user: @customer, drink_item: here.drink_order.drink_item, status: status)
    end
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      row = CastMetricsQuery.new(store: @store, from: @from, to: @to).call.sole
      assert_equal 100, row.stream_sales_points
      assert_equal 3600, row.stream_seconds
      assert_equal 18_000, CastMetricsQuery.new(store: other_store, from: @from, to: @to).call.sole.stream_seconds
    end
  end

  test "H04 開始時刻が残らない旧履歴も確定済み売上を不明行から落とさない" do
    ledger = create_consumed_sales!(booth: @booth_sales, cast_user: @cast_with_sales,
      points: 200, occurred_at: @from + 1.day)
    ledger.stream_session.update!(broadcast_started_at: nil)
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      row = CastMetricsQuery.new(store: @store, from: @from, to: @to).call.sole
      assert_nil row.cast_user
      assert_equal 200, row.stream_sales_points
      assert_equal 0, row.stream_seconds
      assert_nil row.sales_per_hour
    end
  end

  private

  def record_publisher(session, user, source: "ivs_verified")
    session.update!(actual_publisher_user: user, actual_publisher_source: source,
      actual_publisher_recorded_at: session.broadcast_started_at)
  end

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
