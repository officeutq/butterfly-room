# frozen_string_literal: true

require "test_helper"

class SystemAdminManualSettlementsTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @store = Store.create!(name: "Test Store")
    @system_admin = User.create!(email: "sa@example.com", password: "password", role: :system_admin)
    @store_admin  = User.create!(email: "sta@example.com", password: "password", role: :store_admin)
  end

  test "system_admin can access new" do
    sign_in @system_admin, scope: :user
    get "/system_admin/settlements/manual/new"
    assert_response :success
    assert_includes response.body, "マニュアル精算"
  end

  test "non system_admin cannot access" do
    sign_in @store_admin, scope: :user
    get "/system_admin/settlements/manual/new"
    assert_response :forbidden
  end

  test "period_from >= period_to is rejected" do
    sign_in @system_admin, scope: :user

    post "/system_admin/settlements/manual/preview", params: {
      manual_settlement: {
        store_id: @store.id,
        period_from: "2026-02-10 00:00",
        period_to: "2026-02-10 00:00"
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "period_from"
  end

  test "preview calculation matches rules (1pt=1yen, 0.7 floor)" do
    sign_in @system_admin, scope: :user

    travel_to Time.zone.parse("2026-02-01 00:00") do
      create_ledger_entry(points: 101, occurred_at: Time.zone.parse("2026-02-05 12:00"))
      create_ledger_entry(points: 102, occurred_at: Time.zone.parse("2026-02-05 13:00"))
    end

    post "/system_admin/settlements/manual/preview", params: {
      manual_settlement: {
        store_id: @store.id,
        period_from: "2026-02-01 00:00",
        period_to: "2026-03-01 00:00"
      }
    }

    assert_response :success
    gross = 203
    share = (BigDecimal(gross) * BigDecimal("0.7")).floor(0).to_i
    fee = gross - share

    assert_includes response.body, "gross_yen"
    assert_includes response.body, gross.to_s
    assert_includes response.body, share.to_s
    assert_includes response.body, fee.to_s
    assert_not_includes response.body, "carryover_yen"
  end

  test "manual create stores the same amounts as preview and does not apply carryover" do
    sign_in @system_admin, scope: :user

    travel_to Time.zone.parse("2026-02-01 00:00") do
      create_ledger_entry(points: 101, occurred_at: Time.zone.parse("2026-02-05 12:00"))
      create_ledger_entry(points: 102, occurred_at: Time.zone.parse("2026-02-05 13:00"))
    end

    SettlementCarryover.create!(
      store: @store,
      amount_yen: 5_000,
      reason: :min_payout_carryover,
      period_from: Time.zone.parse("2026-01-01 00:00"),
      period_to: Time.zone.parse("2026-02-01 00:00")
    )

    gross = 203
    share = (BigDecimal(gross) * BigDecimal("0.7")).floor(0).to_i
    fee = gross - share

    post "/system_admin/settlements/manual/preview", params: {
      manual_settlement: {
        store_id: @store.id,
        period_from: "2026-02-01 00:00",
        period_to: "2026-03-01 00:00"
      }
    }

    assert_response :success
    assert_includes response.body, gross.to_s
    assert_includes response.body, share.to_s
    assert_includes response.body, fee.to_s
    assert_not_includes response.body, "carryover_yen"

    assert_no_difference -> { SettlementCarryover.count } do
      assert_difference -> { Settlement.where(store: @store, kind: :manual, status: :confirmed).count }, 1 do
        post "/system_admin/settlements/manual", params: {
          manual_settlement: {
            store_id: @store.id,
            period_from: "2026-02-01 00:00",
            period_to: "2026-03-01 00:00"
          }
        }
      end
    end

    assert_redirected_to dashboard_path

    settlement = Settlement.where(store: @store, kind: :manual, status: :confirmed).order(:id).last
    assert_equal gross, settlement.gross_yen
    assert_equal share, settlement.store_share_yen
    assert_equal fee, settlement.platform_fee_yen
    assert_equal 5_000, SettlementCarryover.where(store: @store).sum(:amount_yen)
  end

  test "cannot create overlapping manual settlement" do
    sign_in @system_admin, scope: :user

    Settlement.create!(
      store: @store,
      kind: :manual,
      status: :confirmed,
      confirmed_at: Time.zone.parse("2026-02-01 00:00"),
      period_from: Time.zone.parse("2026-02-01 00:00"),
      period_to: Time.zone.parse("2026-03-01 00:00"),
      gross_yen: 0,
      store_share_yen: 0,
      platform_fee_yen: 0
    )

    post "/system_admin/settlements/manual/preview", params: {
      manual_settlement: {
        store_id: @store.id,
        period_from: "2026-02-10 00:00",
        period_to: "2026-02-20 00:00"
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "既に精算済み"
  end

  private

  def create_ledger_entry(points:, occurred_at:)
    booth = Booth.create!(store: @store, name: "B-#{SecureRandom.hex(4)}", status: :offline)
    cast = User.create!(email: "cast-#{SecureRandom.hex(4)}@example.com", password: "password", role: :cast)
    stream_session = StreamSession.create!(store: @store, booth: booth, status: 0, started_at: Time.current, started_by_cast_user: cast)
    customer = User.create!(email: "customer-#{SecureRandom.hex(4)}@example.com", password: "password", role: :customer)
    item = DrinkItem.create!(store: @store, name: "D-#{SecureRandom.hex(4)}", price_points: points, position: 0, enabled: true)
    order = DrinkOrder.create!(store: @store, booth: booth, stream_session: stream_session, customer_user: customer, drink_item: item, status: :consumed)

    StoreLedgerEntry.create!(
      store: @store,
      stream_session: stream_session,
      drink_order: order,
      points: points,
      occurred_at: occurred_at
    )
  end
end
