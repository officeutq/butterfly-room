# frozen_string_literal: true

require "test_helper"

class Settlements::MonthlyGenerateServiceTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  def setup
    super
    Time.use_zone("Asia/Tokyo") { }
  end

  test "JST month boundary: from inclusive, to exclusive" do
    Time.use_zone("Asia/Tokyo") do
      travel_to Time.zone.local(2026, 4, 15, 12, 0, 0) do
        store = Store.create!(name: "S1")
        booth = Booth.create!(store:, name: "B1", status: :offline, ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123:stage/abc")
        cast = User.create!(email: "cast1@example.com", password: "password", role: :cast)
        customer = User.create!(email: "c1@example.com", password: "password", role: :customer)
        drink_item = DrinkItem.create!(store:, name: "D1", price_points: 1000, position: 1, enabled: true)

        period_from = Time.zone.local(2026, 3, 1, 0, 0, 0)
        period_to   = Time.zone.local(2026, 4, 1, 0, 0, 0)

        ss = StreamSession.create!(store:, booth:, started_by_cast_user: cast, status: :live, started_at: period_from, ivs_stage_arn: booth.ivs_stage_arn)

        # included: exactly at period_from
        o1 = DrinkOrder.create!(store:, booth:, stream_session: ss, customer_user: customer, drink_item:, status: :consumed, consumed_at: period_from)
        StoreLedgerEntry.create!(store:, stream_session: ss, drink_order: o1, points: 5000, occurred_at: period_from)

        # included: just before period_to
        o2 = DrinkOrder.create!(store:, booth:, stream_session: ss, customer_user: customer, drink_item:, status: :consumed, consumed_at: period_to - 1.second)
        StoreLedgerEntry.create!(store:, stream_session: ss, drink_order: o2, points: 5000, occurred_at: period_to - 1.second)

        # excluded: exactly at period_to
        o3 = DrinkOrder.create!(store:, booth:, stream_session: ss, customer_user: customer, drink_item:, status: :consumed, consumed_at: period_to)
        StoreLedgerEntry.create!(store:, stream_session: ss, drink_order: o3, points: 9999, occurred_at: period_to)

        result = Settlements::MonthlyGenerateService.new.call

        assert_equal 0, result.created_count
        assert_equal 0, Settlement.where(store_id: store.id, period_from: period_from, period_to: period_to).count

        carry = SettlementCarryover.where(
          store_id: store.id,
          reason: :min_payout_carryover,
          period_from: period_from,
          period_to: period_to
        )

        assert_equal 1, carry.count
        assert_equal 7000, carry.sum(:amount_yen) # gross=10_000 only (period_toの行は除外される)
      end
    end
  end

  test "70% floor calculation and platform fee" do
    Time.use_zone("Asia/Tokyo") do
      travel_to Time.zone.local(2026, 4, 15, 12, 0, 0) do
        store = Store.create!(name: "S2")
        booth = Booth.create!(store:, name: "B2", status: :offline, ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123:stage/def")
        cast = User.create!(email: "cast2@example.com", password: "password", role: :cast)
        customer = User.create!(email: "c2@example.com", password: "password", role: :customer)
        drink_item = DrinkItem.create!(store:, name: "D2", price_points: 101, position: 1, enabled: true)

        period_from = Time.zone.local(2026, 3, 1, 0, 0, 0)
        ss = StreamSession.create!(store:, booth:, started_by_cast_user: cast, status: :live, started_at: period_from, ivs_stage_arn: booth.ivs_stage_arn)
        o1 = DrinkOrder.create!(store:, booth:, stream_session: ss, customer_user: customer, drink_item:, status: :consumed, consumed_at: period_from + 1.hour)
        StoreLedgerEntry.create!(store:, stream_session: ss, drink_order: o1, points: 101, occurred_at: period_from + 1.hour)

        # carryoverを足して 10,000 以上にして settlement を作らせる
        SettlementCarryover.create!(
          store: store,
          amount_yen: 10_000,
          reason: :min_payout_carryover,
          period_from: Time.zone.local(2026, 2, 1),
          period_to: Time.zone.local(2026, 3, 1),
          created_at: Time.zone.now
        )

        result = Settlements::MonthlyGenerateService.new.call
        assert_equal 1, result.created_count

        settlement = Settlement.order(:id).last
        assert_equal 101, settlement.gross_yen
        # month_share = floor(101*0.7)=70, payable = 70 + 10_000
        assert_equal 10_070, settlement.store_share_yen
        assert_equal 31, settlement.platform_fee_yen
      end
    end
  end

  test "below min payout: no settlement, carryover added once (idempotent)" do
    Time.use_zone("Asia/Tokyo") do
      travel_to Time.zone.local(2026, 4, 15, 12, 0, 0) do
        store = Store.create!(name: "S3")
        booth = Booth.create!(store:, name: "B3", status: :offline, ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123:stage/ghi")
        cast = User.create!(email: "cast3@example.com", password: "password", role: :cast)
        customer = User.create!(email: "c3@example.com", password: "password", role: :customer)
        drink_item = DrinkItem.create!(store:, name: "D3", price_points: 9000, position: 1, enabled: true)

        period_from = Time.zone.local(2026, 3, 1, 0, 0, 0)
        period_to   = Time.zone.local(2026, 4, 1, 0, 0, 0)

        ss = StreamSession.create!(store:, booth:, started_by_cast_user: cast, status: :live, started_at: period_from, ivs_stage_arn: booth.ivs_stage_arn)
        o1 = DrinkOrder.create!(store:, booth:, stream_session: ss, customer_user: customer, drink_item:, status: :consumed, consumed_at: period_from + 2.hours)
        StoreLedgerEntry.create!(store:, stream_session: ss, drink_order: o1, points: 9000, occurred_at: period_from + 2.hours)

        svc = Settlements::MonthlyGenerateService.new

        r1 = svc.call
        assert_equal 0, r1.created_count
        assert_equal 0, Settlement.where(store_id: store.id, period_from:, period_to:).count

        carry = SettlementCarryover.where(store_id: store.id, reason: :min_payout_carryover, period_from:, period_to:)
        assert_equal 1, carry.count
        assert_equal 6300, carry.sum(:amount_yen) # 9000 * 0.7

        # second run should not duplicate carryover
        r2 = svc.call
        assert_equal 0, Settlement.where(store_id: store.id, period_from: period_from, period_to: period_to).count
        assert_equal 0, r2.created_count
        carry2 = SettlementCarryover.where(store_id: store.id, reason: :min_payout_carryover, period_from:, period_to:)
        assert_equal 1, carry2.count
        assert_equal 6300, carry2.sum(:amount_yen)
      end
    end
  end

  test "carryover applied and cleared when payable reaches min payout" do
    Time.use_zone("Asia/Tokyo") do
      travel_to Time.zone.local(2026, 4, 15, 12, 0, 0) do
        store = Store.create!(name: "S4")
        booth = Booth.create!(store:, name: "B4", status: :offline, ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123:stage/jkl")
        cast = User.create!(email: "cast4@example.com", password: "password", role: :cast)
        customer = User.create!(email: "c4@example.com", password: "password", role: :customer)
        drink_item = DrinkItem.create!(store:, name: "D4", price_points: 9000, position: 1, enabled: true)

        # existing carryover 5,000
        SettlementCarryover.create!(
          store: store,
          amount_yen: 5000,
          reason: :min_payout_carryover,
          period_from: Time.zone.local(2026, 2, 1),
          period_to: Time.zone.local(2026, 3, 1),
          created_at: Time.zone.now
        )

        period_from = Time.zone.local(2026, 3, 1, 0, 0, 0)
        period_to   = Time.zone.local(2026, 4, 1, 0, 0, 0)

        ss = StreamSession.create!(store:, booth:, started_by_cast_user: cast, status: :live, started_at: period_from, ivs_stage_arn: booth.ivs_stage_arn)
        o1 = DrinkOrder.create!(store:, booth:, stream_session: ss, customer_user: customer, drink_item:, status: :consumed, consumed_at: period_from + 3.hours)
        StoreLedgerEntry.create!(store:, stream_session: ss, drink_order: o1, points: 9000, occurred_at: period_from + 3.hours)

        # month_share=6300, payable=11300 -> settlement created, carryover cleared
        result = Settlements::MonthlyGenerateService.new.call
        assert_equal 1, result.created_count

        settlement = Settlement.find_by!(store_id: store.id, period_from:, period_to:)
        assert_equal 9000, settlement.gross_yen
        assert_equal 11_300, settlement.store_share_yen
        assert_equal 2700, settlement.platform_fee_yen

        assert_equal 0, SettlementCarryover.where(store_id: store.id).sum(:amount_yen)
        applied = SettlementCarryover.where(store_id: store.id, reason: :applied_to_settlement)
        assert_equal 1, applied.count
        assert_equal(-5000, applied.first.amount_yen)
        assert_equal settlement.id, applied.first.applied_settlement_id
      end
    end
  end

  test "idempotent: settlement not created twice for same period" do
    Time.use_zone("Asia/Tokyo") do
      travel_to Time.zone.local(2026, 4, 15, 12, 0, 0) do
        store = Store.create!(name: "S5")
        booth = Booth.create!(store:, name: "B5", status: :offline, ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123:stage/mno")
        cast = User.create!(email: "cast5@example.com", password: "password", role: :cast)
        customer = User.create!(email: "c5@example.com", password: "password", role: :customer)
        drink_item = DrinkItem.create!(store:, name: "D5", price_points: 20_000, position: 1, enabled: true)

        period_from = Time.zone.local(2026, 3, 1, 0, 0, 0)
        period_to   = Time.zone.local(2026, 4, 1, 0, 0, 0)

        ss = StreamSession.create!(store:, booth:, started_by_cast_user: cast, status: :live, started_at: period_from, ivs_stage_arn: booth.ivs_stage_arn)
        o1 = DrinkOrder.create!(store:, booth:, stream_session: ss, customer_user: customer, drink_item:, status: :consumed, consumed_at: period_from + 1.day)
        StoreLedgerEntry.create!(store:, stream_session: ss, drink_order: o1, points: 20_000, occurred_at: period_from + 1.day)

        svc = Settlements::MonthlyGenerateService.new
        r1 = svc.call
        assert_equal 1, r1.created_count

        r2 = svc.call
        assert_equal 0, r2.created_count

        assert_equal 1, Settlement.where(store_id: store.id, period_from:, period_to:).count
      end
    end
  end

  test "split: one overlapped settlement in the middle -> 2 monthly settlements for gaps" do
    Time.use_zone("Asia/Tokyo") do
      travel_to Time.zone.local(2026, 4, 15, 12, 0, 0) do
        store = Store.create!(name: "S6")
        booth = Booth.create!(store:, name: "B6", status: :offline, ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123:stage/pqr")
        cast = User.create!(email: "cast6@example.com", password: "password", role: :cast)
        customer = User.create!(email: "c6@example.com", password: "password", role: :customer)
        drink_item = DrinkItem.create!(store:, name: "D6", price_points: 1000, position: 1, enabled: true)

        month_from = Time.zone.local(2026, 3, 1, 0, 0, 0)
        month_to   = Time.zone.local(2026, 4, 1, 0, 0, 0)

        ss = StreamSession.create!(store:, booth:, started_by_cast_user: cast, status: :live, started_at: month_from, ivs_stage_arn: booth.ivs_stage_arn)

        # existing (manual) covers [3/10, 3/20)
        Settlement.create!(
          store: store,
          kind: :manual,
          status: :confirmed,
          confirmed_at: Time.zone.parse("2026-03-20 00:00"),
          period_from: Time.zone.parse("2026-03-10 00:00"),
          period_to: Time.zone.parse("2026-03-20 00:00"),
          gross_yen: 0,
          store_share_yen: 0,
          platform_fee_yen: 0
        )

        # gap1: [3/1, 3/10) gross 12_000
        o1 = DrinkOrder.create!(store:, booth:, stream_session: ss, customer_user: customer, drink_item:, status: :consumed, consumed_at: Time.zone.parse("2026-03-05 12:00"))
        StoreLedgerEntry.create!(store:, stream_session: ss, drink_order: o1, points: 12_000, occurred_at: Time.zone.parse("2026-03-05 12:00"))

        # overlap area: [3/10,3/20) gross 50_000 (should be excluded)
        o2 = DrinkOrder.create!(store:, booth:, stream_session: ss, customer_user: customer, drink_item:, status: :consumed, consumed_at: Time.zone.parse("2026-03-15 12:00"))
        StoreLedgerEntry.create!(store:, stream_session: ss, drink_order: o2, points: 50_000, occurred_at: Time.zone.parse("2026-03-15 12:00"))

        # gap2: [3/20, 4/1) gross 8_000
        o3 = DrinkOrder.create!(store:, booth:, stream_session: ss, customer_user: customer, drink_item:, status: :consumed, consumed_at: Time.zone.parse("2026-03-25 12:00"))
        StoreLedgerEntry.create!(store:, stream_session: ss, drink_order: o3, points: 8_000, occurred_at: Time.zone.parse("2026-03-25 12:00"))

        result = Settlements::MonthlyGenerateService.new.call
        assert_equal 2, result.created_count

        settlements = Settlement.where(store_id: store.id, kind: :monthly).order(:period_from).to_a
        assert_equal 2, settlements.size

        s1, s2 = settlements

        assert_equal Time.zone.parse("2026-03-01 00:00"), s1.period_from
        assert_equal Time.zone.parse("2026-03-10 00:00"), s1.period_to
        assert_equal 12_000, s1.gross_yen
        assert_equal 8_400, s1.store_share_yen # 12_000 * 0.7
        assert_equal 3_600, s1.platform_fee_yen

        assert_equal Time.zone.parse("2026-03-20 00:00"), s2.period_from
        assert_equal Time.zone.parse("2026-04-01 00:00"), s2.period_to
        assert_equal 8_000, s2.gross_yen
        assert_equal 5_600, s2.store_share_yen # 8_000 * 0.7
        assert_equal 2_400, s2.platform_fee_yen

        # re-run should not create more (gaps are now covered)
        result2 = Settlements::MonthlyGenerateService.new.call
        assert_equal 0, result2.created_count
        assert_equal 2, Settlement.where(store_id: store.id, kind: :monthly).count
      end
    end
  end

  test "split: fully covered by existing settlements -> 0 monthly settlements and carryover untouched" do
    Time.use_zone("Asia/Tokyo") do
      travel_to Time.zone.local(2026, 4, 15, 12, 0, 0) do
        store = Store.create!(name: "S7")
        booth = Booth.create!(store:, name: "B7", status: :offline, ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123:stage/stu")
        cast = User.create!(email: "cast7@example.com", password: "password", role: :cast)
        customer = User.create!(email: "c7@example.com", password: "password", role: :customer)
        drink_item = DrinkItem.create!(store:, name: "D7", price_points: 1000, position: 1, enabled: true)

        month_from = Time.zone.local(2026, 3, 1, 0, 0, 0)
        month_to   = Time.zone.local(2026, 4, 1, 0, 0, 0)

        ss = StreamSession.create!(store:, booth:, started_by_cast_user: cast, status: :live, started_at: month_from, ivs_stage_arn: booth.ivs_stage_arn)

        # whole month covered by existing manual
        Settlement.create!(
          store: store,
          kind: :manual,
          status: :confirmed,
          confirmed_at: Time.zone.parse("2026-04-01 00:00"),
          period_from: month_from,
          period_to: month_to,
          gross_yen: 0,
          store_share_yen: 0,
          platform_fee_yen: 0
        )

        # ledger exists in month but should be excluded due to full coverage
        o1 = DrinkOrder.create!(store:, booth:, stream_session: ss, customer_user: customer, drink_item:, status: :consumed, consumed_at: Time.zone.parse("2026-03-10 12:00"))
        StoreLedgerEntry.create!(store:, stream_session: ss, drink_order: o1, points: 20_000, occurred_at: Time.zone.parse("2026-03-10 12:00"))

        # existing carryover should remain untouched (because gaps empty)
        SettlementCarryover.create!(
          store: store,
          amount_yen: 5_000,
          reason: :min_payout_carryover,
          period_from: Time.zone.local(2026, 2, 1),
          period_to: Time.zone.local(2026, 3, 1),
          created_at: Time.zone.now
        )

        before_sum = SettlementCarryover.where(store_id: store.id).sum(:amount_yen)

        result = Settlements::MonthlyGenerateService.new.call
        assert_equal 0, result.created_count
        assert_equal 0, Settlement.where(store_id: store.id, kind: :monthly).count

        after_sum = SettlementCarryover.where(store_id: store.id).sum(:amount_yen)
        assert_equal before_sum, after_sum
      end
    end
  end

  test "split: carryover is applied only to the first gap settlement and cleared once" do
    Time.use_zone("Asia/Tokyo") do
      travel_to Time.zone.local(2026, 4, 15, 12, 0, 0) do
        store = Store.create!(name: "S8")
        booth = Booth.create!(store:, name: "B8", status: :offline, ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123:stage/vwx")
        cast = User.create!(email: "cast8@example.com", password: "password", role: :cast)
        customer = User.create!(email: "c8@example.com", password: "password", role: :customer)
        drink_item = DrinkItem.create!(store:, name: "D8", price_points: 1000, position: 1, enabled: true)

        month_from = Time.zone.local(2026, 3, 1, 0, 0, 0)
        ss = StreamSession.create!(store:, booth:, started_by_cast_user: cast, status: :live, started_at: month_from, ivs_stage_arn: booth.ivs_stage_arn)

        # carryover 5,000
        SettlementCarryover.create!(
          store: store,
          amount_yen: 5_000,
          reason: :min_payout_carryover,
          period_from: Time.zone.local(2026, 2, 1),
          period_to: Time.zone.local(2026, 3, 1),
          created_at: Time.zone.now
        )

        # existing (manual) covers [3/10, 3/20)
        Settlement.create!(
          store: store,
          kind: :manual,
          status: :confirmed,
          confirmed_at: Time.zone.parse("2026-03-20 00:00"),
          period_from: Time.zone.parse("2026-03-10 00:00"),
          period_to: Time.zone.parse("2026-03-20 00:00"),
          gross_yen: 0,
          store_share_yen: 0,
          platform_fee_yen: 0
        )

        # gap1 gross 10_000 -> share 7_000
        o1 = DrinkOrder.create!(store:, booth:, stream_session: ss, customer_user: customer, drink_item:, status: :consumed, consumed_at: Time.zone.parse("2026-03-05 12:00"))
        StoreLedgerEntry.create!(store:, stream_session: ss, drink_order: o1, points: 10_000, occurred_at: Time.zone.parse("2026-03-05 12:00"))

        # gap2 gross 10_000 -> share 7_000
        o2 = DrinkOrder.create!(store:, booth:, stream_session: ss, customer_user: customer, drink_item:, status: :consumed, consumed_at: Time.zone.parse("2026-03-25 12:00"))
        StoreLedgerEntry.create!(store:, stream_session: ss, drink_order: o2, points: 10_000, occurred_at: Time.zone.parse("2026-03-25 12:00"))

        # total share 14_000 + carryover 5_000 => 19_000 >= min payout => settlements created
        result = Settlements::MonthlyGenerateService.new.call
        assert_equal 2, result.created_count

        settlements = Settlement.where(store_id: store.id, kind: :monthly).order(:period_from).to_a
        assert_equal 2, settlements.size

        s1, s2 = settlements
        assert_equal 12_000, s1.store_share_yen # 7_000 + 5_000 carryover
        assert_equal 7_000, s2.store_share_yen  # carryover not applied

        assert_equal 0, SettlementCarryover.where(store_id: store.id).sum(:amount_yen)

        applied = SettlementCarryover.where(store_id: store.id, reason: :applied_to_settlement)
        assert_equal 1, applied.count
        assert_equal(-5_000, applied.first.amount_yen)
        assert_equal s1.id, applied.first.applied_settlement_id
      end
    end
  end
end
