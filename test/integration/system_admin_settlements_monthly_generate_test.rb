# frozen_string_literal: true

require "test_helper"

class SystemAdminSettlementsMonthlyGenerateTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @store = Store.create!(name: "Monthly Generate Store")
    @system_admin = User.create!(email: "monthly-generate-system-admin@example.com", password: "password", role: :system_admin)
    @store_admin = User.create!(email: "monthly-generate-store-admin@example.com", password: "password", role: :store_admin)
  end

  test "system_admin index shows monthly generation form" do
    sign_in @system_admin, scope: :user

    get system_admin_settlements_path

    assert_response :success
    assert_select "form[action=?]", generate_monthly_system_admin_settlements_path
    assert_select "input[name=?]", "target_month", count: 0
    assert_includes response.body, "月次精算生成"
    assert_includes response.body, "前月分を生成"
  end

  test "system_admin can generate monthly settlements and records created event" do
    sign_in @system_admin, scope: :user

    Time.use_zone("Asia/Tokyo") do
      travel_to Time.zone.local(2026, 4, 15, 12, 0, 0) do
        create_ledger_entry(points: 20_000, occurred_at: Time.zone.parse("2026-03-05 12:00"))

        assert_difference -> { Settlement.where(store: @store, kind: :monthly, status: :draft).count }, 1 do
          assert_difference -> { SettlementEvent.created.count }, 1 do
            post generate_monthly_system_admin_settlements_path
          end
        end
      end
    end

    assert_redirected_to system_admin_settlements_path(month: "2026-03")
    assert_match "作成: 1件", flash[:notice]
    assert_match "スキップ: 0件", flash[:notice]
    assert_match "繰越: 0件", flash[:notice]

    settlement = Settlement.where(store: @store, kind: :monthly, status: :draft).order(:id).last
    assert_equal Time.zone.parse("2026-03-01 00:00"), settlement.period_from
    assert_equal Time.zone.parse("2026-04-01 00:00"), settlement.period_to
    assert_equal 20_000, settlement.gross_yen
    assert_equal 14_000, settlement.store_share_yen
    assert_equal 6_000, settlement.platform_fee_yen

    event = settlement.settlement_events.created.order(:id).last
    assert_equal @system_admin, event.actor_user
    assert_equal "monthly_generate_service", event.metadata["source"]
    assert_equal 20_000, event.metadata["gross_yen"]
    assert_equal 14_000, event.metadata["store_share_yen"]
    assert_equal 6_000, event.metadata["platform_fee_yen"]
    assert_equal 0, event.metadata["carryover_applied_yen"]
  end

  test "below min payout creates carryover but no settlement event" do
    sign_in @system_admin, scope: :user

    Time.use_zone("Asia/Tokyo") do
      travel_to Time.zone.local(2026, 4, 15, 12, 0, 0) do
        create_ledger_entry(points: 9_000, occurred_at: Time.zone.parse("2026-03-05 12:00"))

        assert_no_difference -> { Settlement.count } do
          assert_no_difference -> { SettlementEvent.created.count } do
            assert_difference -> { SettlementCarryover.where(store: @store, reason: :min_payout_carryover).count }, 1 do
              post generate_monthly_system_admin_settlements_path
            end
          end
        end
      end
    end

    assert_redirected_to system_admin_settlements_path(month: "2026-03")
    assert_match "作成: 0件", flash[:notice]
    assert_match "スキップ: 1件", flash[:notice]
    assert_match "繰越: 1件", flash[:notice]

    carryover = SettlementCarryover.where(store: @store, reason: :min_payout_carryover).order(:id).last
    assert_equal 6_300, carryover.amount_yen
  end

  test "non system_admin cannot generate monthly settlements" do
    sign_in @store_admin, scope: :user

    assert_no_difference -> { Settlement.count } do
      post generate_monthly_system_admin_settlements_path
    end

    assert_response :forbidden
  end

  private

  def create_ledger_entry(points:, occurred_at:)
    booth = Booth.create!(store: @store, name: "Monthly Booth #{SecureRandom.hex(4)}", status: :offline)
    cast = User.create!(email: "monthly-cast-#{SecureRandom.hex(4)}@example.com", password: "password", role: :cast)
    stream_session = StreamSession.create!(store: @store, booth: booth, status: 0, started_at: occurred_at, started_by_cast_user: cast)
    customer = User.create!(email: "monthly-customer-#{SecureRandom.hex(4)}@example.com", password: "password", role: :customer)
    item = DrinkItem.create!(store: @store, name: "Monthly Drink #{SecureRandom.hex(4)}", price_points: points, position: 0, enabled: true)
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
