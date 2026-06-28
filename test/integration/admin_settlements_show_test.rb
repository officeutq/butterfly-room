# frozen_string_literal: true

require "test_helper"

class AdminSettlementsShowTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "store1")
    @store_admin = User.create!(email: "admin_settlement_show@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "admin_settlement_exporter@example.com", password: "password", role: :system_admin)
    StoreMembership.create!(store: @store, user: @store_admin, membership_role: :admin)

    @confirmed = Settlement.create!(
      store: @store,
      kind: :monthly,
      status: :confirmed,
      period_from: Time.use_zone("Asia/Tokyo") { Time.zone.today.prev_month.beginning_of_month.beginning_of_day },
      period_to: Time.use_zone("Asia/Tokyo") { Time.zone.today.beginning_of_month.beginning_of_day },
      gross_yen: 10_000,
      store_share_yen: 7_000,
      platform_fee_yen: 3_000,
      confirmed_at: Time.use_zone("Asia/Tokyo") { Time.zone.now }
    )

    @draft = Settlement.create!(
      store: @store,
      kind: :monthly,
      status: :draft,
      period_from: Time.use_zone("Asia/Tokyo") { Time.zone.today.prev_month.prev_month.beginning_of_month.beginning_of_day },
      period_to: Time.use_zone("Asia/Tokyo") { Time.zone.today.prev_month.beginning_of_month.beginning_of_day },
      gross_yen: 5_000,
      store_share_yen: 3_500,
      platform_fee_yen: 1_500
    )

    @exported = Settlement.create!(
      store: @store,
      kind: :monthly,
      status: :exported,
      period_from: Time.zone.parse("2020-01-01 00:00:00"),
      period_to: Time.zone.parse("2020-02-01 00:00:00"),
      gross_yen: 20_000,
      store_share_yen: 14_000,
      platform_fee_yen: 6_000,
      confirmed_at: Time.zone.parse("2020-02-02 00:00:00"),
      exported_at: Time.zone.parse("2020-02-03 00:00:00"),
      exported_by_user: @system_admin,
      export_format: "sbi_furikomi_csv",
      export_file_key: "admin-show-export-key",
      payout_bank_code: "0038",
      payout_branch_code: "101",
      payout_account_type: :ordinary,
      payout_account_number: "1234567",
      payout_account_holder_kana: "テストテンポ"
    )

    @paid = Settlement.create!(
      store: @store,
      kind: :monthly,
      status: :paid,
      period_from: Time.zone.parse("2020-02-01 00:00:00"),
      period_to: Time.zone.parse("2020-03-01 00:00:00"),
      gross_yen: 30_000,
      store_share_yen: 21_000,
      platform_fee_yen: 9_000,
      confirmed_at: Time.zone.parse("2020-03-02 00:00:00"),
      exported_at: Time.zone.parse("2020-03-03 00:00:00"),
      exported_by_user: @system_admin,
      export_format: "sbi_furikomi_csv",
      export_file_key: "admin-show-paid-export-key",
      payout_bank_code: "0038",
      payout_branch_code: "101",
      payout_account_type: :ordinary,
      payout_account_number: "1234567",
      payout_account_holder_kana: "テストテンポ",
      paid_at: Time.zone.parse("2020-03-10 12:00:00"),
      paid_by_user: @system_admin
    )

    @other_store = Store.create!(name: "other-store")
    @other_paid = Settlement.create!(
      store: @other_store,
      kind: :monthly,
      status: :paid,
      period_from: Time.zone.parse("2020-02-01 00:00:00"),
      period_to: Time.zone.parse("2020-03-01 00:00:00"),
      gross_yen: 40_000,
      store_share_yen: 28_000,
      platform_fee_yen: 12_000,
      confirmed_at: Time.zone.parse("2020-03-02 00:00:00"),
      exported_at: Time.zone.parse("2020-03-03 00:00:00"),
      exported_by_user: @system_admin,
      export_format: "sbi_furikomi_csv",
      export_file_key: "admin-show-other-paid-export-key",
      payout_bank_code: "0038",
      payout_branch_code: "102",
      payout_account_type: :ordinary,
      payout_account_number: "2345678",
      payout_account_holder_kana: "ホカテンポ",
      paid_at: Time.zone.parse("2020-03-10 12:00:00"),
      paid_by_user: @system_admin
    )
  end

  test "store_admin can view confirmed settlement detail" do
    sign_in @store_admin, scope: :user

    post admin_current_store_path, params: { store_id: @store.id }
    follow_redirect!
    assert_response :success

    get admin_settlement_path(@confirmed)
    assert_response :success

    body = response.body
    refute_includes body, "振込先口座"
    refute_includes body, "export_file_key"
    refute_includes body, "支払明細書PDFをダウンロード"
  end

  test "store_admin cannot view draft settlement detail" do
    sign_in @store_admin, scope: :user

    post admin_current_store_path, params: { store_id: @store.id }
    follow_redirect!
    assert_response :success

    get admin_settlement_path(@draft)
    assert_response :not_found
  end

  test "store_admin can download own paid payment statement" do
    sign_in @store_admin, scope: :user
    select_current_store

    get payment_statement_admin_settlement_path(@paid)
    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert response.body.start_with?("%PDF")
    assert_includes response.headers.fetch("Content-Disposition"), "attachment"
    assert_includes response.headers.fetch("Content-Disposition"), "payment_statement_PS-#{format('%08d', @paid.id)}.pdf"
  end

  test "store_admin can see payment statement button only for paid settlement" do
    sign_in @store_admin, scope: :user
    select_current_store

    get admin_settlement_path(@paid)
    assert_response :success
    assert_includes response.body, "支払明細書PDFをダウンロード"

    get admin_settlement_path(@exported)
    assert_response :success
    refute_includes response.body, "支払明細書PDFをダウンロード"
  end

  test "store_admin cannot download payment statement for other store or non paid settlements" do
    [ @other_paid, @draft, @confirmed, @exported ].each do |settlement|
      sign_in @store_admin, scope: :user
      select_current_store
      get payment_statement_admin_settlement_path(settlement)
      assert_response :not_found
    end
  end

  private

  def select_current_store
    post admin_current_store_path, params: { store_id: @store.id }
    follow_redirect!
    assert_response :success
  end
end
