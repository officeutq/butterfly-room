# frozen_string_literal: true

require "pdf/reader"
require "test_helper"

class Settlements::PaymentStatementPdfServiceTest < ActiveSupport::TestCase
  setup do
    @store = Store.create!(name: "PDFテスト店舗")
    @actor = User.create!(email: "payment-statement-service@example.com", password: "password", role: :system_admin)
  end

  test "paid settlement generates store payment statement PDF" do
    settlement = create_paid_settlement

    result =
      Settlements::PaymentStatementPdfService.new(
        settlement: settlement,
        issued_at: Time.zone.parse("2026-05-11 09:00:00")
      ).call

    assert_equal "payment_statement_PS-#{format('%08d', settlement.id)}.pdf", result[:filename]
    assert_equal "application/pdf", result[:content_type]
    assert result[:data].start_with?("%PDF")

    text = pdf_text(result[:data])
    assert_includes text, "支払明細書"
    assert_includes text, "PS-#{format('%08d', settlement.id)}"
    assert_includes text, "PDFテスト店舗"
    assert_includes text, "2026年5月10日 15:30"
    assert_includes text, "30,000円"
    assert_includes text, "9,000円"
    assert_includes text, "21,000円"
    assert_includes text, "***4567"
  end

  test "system admin copy uses admin copy title and filename" do
    settlement = create_paid_settlement

    result =
      Settlements::PaymentStatementPdfService.new(
        settlement: settlement,
        copy: true,
        issued_at: Time.zone.parse("2026-05-11 09:00:00")
      ).call

    assert_equal "payment_statement_PS-#{format('%08d', settlement.id)}_admin_copy.pdf", result[:filename]
    assert_includes pdf_text(result[:data]), "支払明細書（運営控え）"
  end

  test "rejects non paid settlement statuses" do
    %i[draft confirmed exported].each do |status|
      store = Store.create!(name: "PDF非支払店舗-#{status}-#{SecureRandom.hex(4)}")
      settlement = create_settlement(status: status, store: store)

      assert_raises(ArgumentError) do
        Settlements::PaymentStatementPdfService.new(settlement: settlement).call
      end
    end
  end

  test "uses settlement payout snapshot instead of current store payout account" do
    settlement = create_paid_settlement

    StorePayoutAccount.create!(
      store: @store,
      payout_method: :manual_bank,
      status: :active,
      input_account_kind: :bank,
      bank_code: "9999",
      branch_code: "202",
      account_type: :current,
      account_number: "7654321",
      account_holder_kana: "カレントコウザ"
    )

    text = pdf_text(Settlements::PaymentStatementPdfService.new(settlement: settlement).call[:data])

    assert_includes text, "0038"
    assert_includes text, "101"
    assert_includes text, "普通"
    assert_includes text, "***4567"
    refute_includes text, "9999"
    refute_includes text, "7654321"
    refute_includes text, "カレントコウザ"
  end

  private

  def pdf_text(data)
    PDF::Reader.new(StringIO.new(data)).pages.map(&:text).join("\n")
  end

  def create_paid_settlement
    create_settlement(status: :paid)
  end

  def create_settlement(status:, store: @store)
    base = {
      store: store,
      kind: :monthly,
      status: status,
      period_from: Time.zone.parse("2026-05-01 00:00:00"),
      period_to: Time.zone.parse("2026-06-01 00:00:00"),
      gross_yen: 30_000,
      store_share_yen: 21_000,
      platform_fee_yen: 9_000
    }

    if %i[confirmed exported paid].include?(status)
      base[:confirmed_at] = Time.zone.parse("2026-06-02 10:00:00")
    end

    if %i[exported paid].include?(status)
      base.merge!(
        exported_at: Time.zone.parse("2026-06-03 10:00:00"),
        exported_by_user: @actor,
        export_format: "sbi_furikomi_csv",
        export_file_key: "test-export-key",
        payout_bank_code: "0038",
        payout_branch_code: "101",
        payout_account_type: :ordinary,
        payout_account_number: "1234567",
        payout_account_holder_kana: "テストテンポ"
      )
    end

    if status == :paid
      base.merge!(
        paid_at: Time.zone.parse("2026-05-10 15:30:00"),
        paid_by_user: @actor
      )
    end

    Settlement.create!(base)
  end
end
