# frozen_string_literal: true

require "test_helper"

class SystemAdminSettlementsMarkPaidTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @store = Store.create!(name: "Paid Store")
    @system_admin = User.create!(email: "paid-system-admin@example.com", password: "password", role: :system_admin)

    @settlement = Settlement.create!(
      store: @store,
      kind: :monthly,
      status: :exported,
      period_from: Time.zone.parse("2026-04-01 00:00:00"),
      period_to: Time.zone.parse("2026-05-01 00:00:00"),
      gross_yen: 20_000,
      store_share_yen: 14_000,
      platform_fee_yen: 6_000,
      confirmed_at: Time.zone.parse("2026-05-02 00:00:00"),
      exported_at: Time.zone.parse("2026-05-03 00:00:00"),
      exported_by_user: @system_admin,
      export_format: "sbi_furikomi_csv",
      export_file_key: "settlement-export-key",
      payout_bank_code: "0038",
      payout_branch_code: "101",
      payout_account_type: :ordinary,
      payout_account_number: "1234567",
      payout_account_holder_kana: "ﾃｽﾄ"
    )
  end

  test "mark_paid stores paid_at and paid_by_user and records event" do
    sign_in @system_admin, scope: :user

    paid_time = Time.zone.parse("2026-05-10 12:34:56")
    travel_to paid_time do
      assert_difference -> { SettlementEvent.marked_paid.count }, 1 do
        post mark_paid_system_admin_settlement_path(@settlement), params: { paid_confirm: "1" }
      end
    end

    assert_redirected_to system_admin_settlement_path(@settlement)

    @settlement.reload
    assert_predicate @settlement, :paid?
    assert_equal paid_time.to_i, @settlement.paid_at.to_i
    assert_equal @system_admin, @settlement.paid_by_user

    event = @settlement.settlement_events.marked_paid.order(:id).last
    assert_equal @system_admin, event.actor_user
  end

  test "mark_paid requires confirmation checkbox" do
    sign_in @system_admin, scope: :user

    assert_no_difference -> { SettlementEvent.marked_paid.count } do
      post mark_paid_system_admin_settlement_path(@settlement)
    end

    assert_redirected_to system_admin_settlement_path(@settlement)
    assert_predicate @settlement.reload, :exported?
    assert_nil @settlement.paid_at
    assert_nil @settlement.paid_by_user
  end
end
