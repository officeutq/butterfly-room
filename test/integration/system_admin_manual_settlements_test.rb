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
      booth = Booth.create!(store: @store, name: "B", status: :offline)
      cast = User.create!(email: "cast@example.com", password: "password", role: :cast)
      ss = StreamSession.create!(store: @store, booth: booth, status: 0, started_at: Time.current, started_by_cast_user: cast)

      customer = User.create!(email: "c@example.com", password: "password", role: :customer)
      item = DrinkItem.create!(store: @store, name: "D", price_points: 100, position: 0, enabled: true)

      order1 = DrinkOrder.create!(store: @store, booth: booth, stream_session: ss, customer_user: customer, drink_item: item, status: :consumed)
      order2 = DrinkOrder.create!(store: @store, booth: booth, stream_session: ss, customer_user: customer, drink_item: item, status: :consumed)

      StoreLedgerEntry.create!(store: @store, stream_session: ss, drink_order: order1, points: 101, occurred_at: Time.zone.parse("2026-02-05 12:00"))
      StoreLedgerEntry.create!(store: @store, stream_session: ss, drink_order: order2, points: 102, occurred_at: Time.zone.parse("2026-02-05 13:00"))
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
end
