# frozen_string_literal: true

require "test_helper"

class SystemAdminSettlementsShowTest < ActionDispatch::IntegrationTest
  setup do
    @system_admin = User.create!(email: "system-admin-payment-statement@example.com", password: "password", role: :system_admin)
    @store = Store.create!(name: "system-admin-pdf-store")

    @draft = create_settlement(status: :draft, period_from: "2020-01-01", period_to: "2020-02-01")
    @confirmed = create_settlement(status: :confirmed, period_from: "2020-02-01", period_to: "2020-03-01")
    @exported = create_settlement(status: :exported, period_from: "2020-03-01", period_to: "2020-04-01")
    @paid = create_settlement(status: :paid, period_from: "2020-04-01", period_to: "2020-05-01")

    other_store = Store.create!(name: "system-admin-other-pdf-store")
    @other_paid = create_settlement(
      store: other_store,
      status: :paid,
      period_from: "2020-04-01",
      period_to: "2020-05-01"
    )
  end

  test "system_admin can download paid payment statement admin copy for any store" do
    sign_in @system_admin, scope: :user

    [ @paid, @other_paid ].each do |settlement|
      get payment_statement_system_admin_settlement_path(settlement)

      assert_response :success
      assert_equal "application/pdf", response.media_type
      assert response.body.start_with?("%PDF")
      assert_includes response.headers.fetch("Content-Disposition"), "attachment"
      assert_includes response.headers.fetch("Content-Disposition"), "payment_statement_PS-#{format('%08d', settlement.id)}_admin_copy.pdf"
    end
  end

  test "system_admin cannot download payment statement for non paid settlements" do
    [ @draft, @confirmed, @exported ].each do |settlement|
      sign_in @system_admin, scope: :user
      get payment_statement_system_admin_settlement_path(settlement)
      assert_response :not_found
    end
  end

  test "system_admin settlement detail shows payment statement button only for paid settlement" do
    sign_in @system_admin, scope: :user

    get system_admin_settlement_path(@paid)
    assert_response :success
    assert_includes response.body, "支払明細書（運営控え）PDFをダウンロード"

    get system_admin_settlement_path(@exported)
    assert_response :success
    refute_includes response.body, "支払明細書（運営控え）PDFをダウンロード"
  end

  private

  def create_settlement(status:, period_from:, period_to:, store: @store)
    base = {
      store: store,
      kind: :monthly,
      status: status,
      period_from: Time.zone.parse("#{period_from} 00:00:00"),
      period_to: Time.zone.parse("#{period_to} 00:00:00"),
      gross_yen: 30_000,
      store_share_yen: 21_000,
      platform_fee_yen: 9_000
    }

    if %i[confirmed exported paid].include?(status)
      base[:confirmed_at] = base[:period_to] + 1.day
    end

    if %i[exported paid].include?(status)
      base.merge!(
        exported_at: base[:period_to] + 2.days,
        exported_by_user: @system_admin,
        export_format: "sbi_furikomi_csv",
        export_file_key: "system-admin-show-export-key-#{SecureRandom.hex(4)}",
        payout_bank_code: "0038",
        payout_branch_code: "101",
        payout_account_type: :ordinary,
        payout_account_number: "1234567",
        payout_account_holder_kana: "テストテンポ"
      )
    end

    if status == :paid
      base.merge!(
        paid_at: base[:period_to] + 10.days,
        paid_by_user: @system_admin
      )
    end

    Settlement.create!(base)
  end
end
