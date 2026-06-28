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

  test "draft settlement can change amount and period" do
    settlement = create_draft_settlement

    settlement.update!(
      gross_yen: 10_000,
      store_share_yen: 7_000,
      platform_fee_yen: 3_000,
      period_to: Time.zone.parse("2026-08-01 00:00:00")
    )

    assert_equal 10_000, settlement.gross_yen
    assert_equal Time.zone.parse("2026-08-01 00:00:00"), settlement.period_to
  end

  test "confirmed settlement cannot change amount" do
    settlement = create_confirmed_settlement

    assert_not settlement.update(gross_yen: settlement.gross_yen + 1)
    assert settlement.errors[:gross_yen].present?
  end

  test "exported settlement cannot change period" do
    settlement = create_exported_settlement

    assert_not settlement.update(period_from: settlement.period_from - 1.day)
    assert settlement.errors[:period_from].present?
  end

  test "paid settlement cannot change amount" do
    settlement = create_paid_settlement

    assert_not settlement.update(store_share_yen: settlement.store_share_yen + 1)
    assert settlement.errors[:store_share_yen].present?
  end

  test "confirmed settlement remains immutable even if status is changed back" do
    settlement = create_confirmed_settlement

    assert_not settlement.update(status: :draft, gross_yen: settlement.gross_yen + 1)
    assert settlement.errors[:gross_yen].present?
  end

  test "exported settlement cannot change payout snapshot" do
    settlement = create_exported_settlement

    assert_not settlement.update(payout_account_number: "7654321")
    assert settlement.errors[:payout_account_number].present?
  end

  test "paid settlement cannot change payout snapshot" do
    settlement = create_paid_settlement

    assert_not settlement.update(payout_bank_code: "9999")
    assert settlement.errors[:payout_bank_code].present?
  end

  test "exported payout snapshot remains immutable even if status is changed back" do
    settlement = create_exported_settlement

    assert_not settlement.update(status: :confirmed, payout_branch_code: "999")
    assert settlement.errors[:payout_branch_code].present?
  end

  test "valid lifecycle metadata updates are allowed without changing amount or period" do
    settlement = create_draft_settlement
    user = create_system_admin("settlement-lifecycle@example.com")

    assert settlement.update(status: :confirmed, confirmed_at: Time.zone.parse("2026-07-02 00:00:00"))

    assert settlement.update(
      status: :exported,
      exported_at: Time.zone.parse("2026-07-03 00:00:00"),
      exported_by_user: user,
      export_format: "sbi_furikomi_csv",
      payout_bank_code: "0038",
      payout_branch_code: "101",
      payout_account_type: :ordinary,
      payout_account_number: "1234567",
      payout_account_holder_kana: "ﾃｽﾄ"
    )

    assert settlement.update(
      status: :paid,
      paid_at: Time.zone.parse("2026-07-04 00:00:00"),
      paid_by_user: user
    )
  end

  private

  def create_draft_settlement
    Settlement.create!(
      store: Store.create!(name: "store-#{SecureRandom.hex(4)}"),
      kind: :monthly,
      status: :draft,
      period_from: Time.zone.parse("2026-07-01 00:00:00"),
      period_to: Time.zone.parse("2026-07-15 00:00:00"),
      gross_yen: 9_000,
      store_share_yen: 6_300,
      platform_fee_yen: 2_700
    )
  end

  def create_confirmed_settlement
    create_draft_settlement.tap do |settlement|
      settlement.update!(
        status: :confirmed,
        confirmed_at: Time.zone.parse("2026-07-16 00:00:00")
      )
    end
  end

  def create_exported_settlement
    user = create_system_admin("settlement-exported@example.com")

    create_confirmed_settlement.tap do |settlement|
      settlement.update!(
        status: :exported,
        exported_at: Time.zone.parse("2026-07-17 00:00:00"),
        exported_by_user: user,
        export_format: "sbi_furikomi_csv",
        payout_bank_code: "0038",
        payout_branch_code: "101",
        payout_account_type: :ordinary,
        payout_account_number: "1234567",
        payout_account_holder_kana: "ﾃｽﾄ"
      )
    end
  end

  def create_paid_settlement
    user = create_system_admin("settlement-paid@example.com")

    create_exported_settlement.tap do |settlement|
      settlement.update!(
        status: :paid,
        paid_at: Time.zone.parse("2026-07-18 00:00:00"),
        paid_by_user: user
      )
    end
  end

  def create_system_admin(email)
    User.create!(email: email, password: "password", role: :system_admin)
  end
end
