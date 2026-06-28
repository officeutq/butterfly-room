# frozen_string_literal: true

require "test_helper"

class SettlementTest < ActiveSupport::TestCase
  test "exact same period is unique per store at DB level" do
    store = Store.create!(name: "store")

    from = Time.zone.parse("2026-02-01 00:00:00")
    to   = Time.zone.parse("2026-03-01 00:00:00")

    Settlement.create!(
      store: store,
      kind: :monthly,
      status: :draft,
      period_from: from,
      period_to: to
    )

    assert_raises(ActiveRecord::ExclusionViolation) do
      Settlement.create!(
        store: store,
        kind: :monthly,
        status: :draft,
        period_from: from,
        period_to: to
      )
    end
  end

  test "overlapping period is rejected at DB level (exclude constraint)" do
    store = Store.create!(name: "store")

    Settlement.create!(
      store: store,
      kind: :monthly,
      status: :draft,
      period_from: Time.zone.parse("2026-02-01 00:00:00"),
      period_to:   Time.zone.parse("2026-03-01 00:00:00")
    )

    assert_raises(ActiveRecord::StatementInvalid) do
      Settlement.create!(
        store: store,
        kind: :monthly,
        status: :draft,
        period_from: Time.zone.parse("2026-02-15 00:00:00"),
        period_to:   Time.zone.parse("2026-03-15 00:00:00")
      )
    end
  end

  test "period_from must be before period_to (model validation)" do
    store = Store.create!(name: "store")

    s = Settlement.new(
      store: store,
      kind: :monthly,
      status: :draft,
      period_from: Time.zone.parse("2026-03-01 00:00:00"),
      period_to:   Time.zone.parse("2026-03-01 00:00:00")
    )

    assert_not s.valid?
    assert_includes s.errors[:period_to], "must be after period_from"
  end

  test "period_from must be before period_to (DB check constraint)" do
    store = Store.create!(name: "store")

    s = Settlement.new(
      store: store,
      kind: :monthly,
      status: :draft,
      period_from: Time.zone.parse("2026-03-01 00:00:00"),
      period_to:   Time.zone.parse("2026-03-01 00:00:00")
    )

    assert_raises(ActiveRecord::StatementInvalid) do
      s.save!(validate: false)
    end
  end

  test "paid settlement requires paid_at" do
    store = Store.create!(name: "store")
    user = User.create!(email: "settlement-exporter@example.com", password: "password", role: :system_admin)

    settlement = Settlement.new(
      store: store,
      kind: :monthly,
      status: :paid,
      period_from: Time.zone.parse("2026-04-01 00:00:00"),
      period_to: Time.zone.parse("2026-05-01 00:00:00"),
      confirmed_at: Time.zone.parse("2026-05-02 00:00:00"),
      exported_at: Time.zone.parse("2026-05-03 00:00:00"),
      exported_by_user: user,
      export_format: "sbi_furikomi_csv",
      payout_bank_code: "0038",
      payout_branch_code: "101",
      payout_account_type: :ordinary,
      payout_account_number: "1234567",
      payout_account_holder_kana: "ﾃｽﾄ"
    )

    assert_not settlement.valid?
    assert settlement.errors.of_kind?(:paid_at, :blank)
  end

  test "paid settlement can omit paid_by_user for future automatic payment results" do
    store = Store.create!(name: "store")
    user = User.create!(email: "settlement-exporter@example.com", password: "password", role: :system_admin)

    settlement = Settlement.new(
      store: store,
      kind: :monthly,
      status: :paid,
      period_from: Time.zone.parse("2026-05-01 00:00:00"),
      period_to: Time.zone.parse("2026-06-01 00:00:00"),
      confirmed_at: Time.zone.parse("2026-06-02 00:00:00"),
      exported_at: Time.zone.parse("2026-06-03 00:00:00"),
      exported_by_user: user,
      export_format: "sbi_furikomi_csv",
      payout_bank_code: "0038",
      payout_branch_code: "101",
      payout_account_type: :ordinary,
      payout_account_number: "1234567",
      payout_account_holder_kana: "ﾃｽﾄ",
      paid_at: Time.zone.parse("2026-06-04 00:00:00")
    )

    assert settlement.valid?
  end
end
