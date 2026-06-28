# frozen_string_literal: true

require "test_helper"

class Settlements::SbiFurikomiCsvExportServiceTest < ActiveSupport::TestCase
  setup do
    @actor = create_system_admin("sbi-exporter-#{SecureRandom.hex(4)}@example.com")
  end

  test "exports confirmed settlement and stores payout snapshot" do
    store = Store.create!(name: "store-#{SecureRandom.hex(4)}")
    account = create_payout_account(store: store)
    settlement = create_confirmed_settlement(store: store)
    result = nil

    assert_difference -> { SettlementExport.count }, 1 do
      with_sbi_env do
        result = Settlements::SbiFurikomiCsvExportService.new(
          actor_user: @actor,
          settlements: [ settlement ]
        ).call
      end
    end

    assert result[:ok], result[:message]

    export = result[:created_exports].first
    assert_equal 1, export.record_count
    assert_equal settlement.store_share_yen, export.total_amount_yen
    assert export.file.attached?

    settlement.reload
    assert_equal "exported", settlement.status
    assert_equal "sbi_furikomi_csv", settlement.export_format
    assert_equal export.file.blob.key, settlement.export_file_key
    assert_equal @actor, settlement.exported_by_user
    assert_equal account.bank_code, settlement.payout_bank_code
    assert_equal account.branch_code, settlement.payout_branch_code
    assert_equal account.account_type, settlement.payout_account_type
    assert_equal account.account_number, settlement.payout_account_number
    assert_equal account.account_holder_kana, settlement.payout_account_holder_kana
    assert settlement.settlement_events.exported.exists?(actor_user: @actor)
  end

  test "later active payout account changes do not change exported settlement snapshot" do
    store = Store.create!(name: "store-#{SecureRandom.hex(4)}")
    account = create_payout_account(store: store)
    settlement = create_confirmed_settlement(store: store)

    with_sbi_env do
      result = Settlements::SbiFurikomiCsvExportService.new(
        actor_user: @actor,
        settlements: [ settlement ]
      ).call
      assert result[:ok], result[:message]
    end

    settlement.reload
    original_snapshot = settlement.attributes.slice(
      "payout_bank_code",
      "payout_branch_code",
      "payout_account_type",
      "payout_account_number",
      "payout_account_holder_kana"
    )

    account.update!(status: :inactive)
    create_payout_account(
      store: store,
      bank_code: "9999",
      branch_code: "202",
      account_type: :current,
      account_number: "7654321",
      account_holder_kana: "ｺｳｼﾝｻｷ"
    )

    assert_equal original_snapshot, settlement.reload.attributes.slice(*original_snapshot.keys)
  end

  private

  def create_confirmed_settlement(store:)
    Settlement.create!(
      store: store,
      kind: :monthly,
      status: :confirmed,
      period_from: Time.zone.parse("2026-08-01 00:00:00"),
      period_to: Time.zone.parse("2026-09-01 00:00:00"),
      gross_yen: 10_000,
      store_share_yen: 7_000,
      platform_fee_yen: 3_000,
      confirmed_at: Time.zone.parse("2026-09-02 00:00:00")
    )
  end

  def create_payout_account(
    store:,
    bank_code: "0038",
    branch_code: "101",
    account_type: :ordinary,
    account_number: "1234567",
    account_holder_kana: "ﾃｽﾄ"
  )
    StorePayoutAccount.create!(
      store: store,
      payout_method: :manual_bank,
      status: :active,
      input_account_kind: :bank,
      bank_code: bank_code,
      branch_code: branch_code,
      account_type: account_type,
      account_number: account_number,
      account_holder_kana: account_holder_kana
    )
  end

  def create_system_admin(email)
    User.create!(email: email, password: "password", role: :system_admin)
  end

  def with_sbi_env
    values = {
      "SOUTOKU_FURIKOMI_CLIENT_CODE" => "2000000001",
      "SOUTOKU_FURIKOMI_CLIENT_NAME" => "ﾊﾞﾀﾌﾗｲﾍﾞ",
      "SOUTOKU_FURIKOMI_BANK_CODE" => "0038",
      "SOUTOKU_FURIKOMI_BANK_NAME" => "ｽﾐｼﾝSBIﾈｯﾄ",
      "SOUTOKU_FURIKOMI_BRANCH_CODE" => "106",
      "SOUTOKU_FURIKOMI_BRANCH_NAME" => "ﾎﾝﾃﾝ",
      "SOUTOKU_FURIKOMI_ACCOUNT_TYPE" => "1",
      "SOUTOKU_FURIKOMI_ACCOUNT_NUMBER" => "1234567"
    }
    previous = {}

    values.each do |key, value|
      previous[key] = ENV[key]
      ENV[key] = value
    end

    yield
  ensure
    previous.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end
