# frozen_string_literal: true

require "test_helper"

class AdminStorePayoutAccountTest < ActionDispatch::IntegrationTest
  setup do
    @store1 = Store.create!(name: "store1")
    @store2 = Store.create!(name: "store2")

    @store_admin  = User.create!(email: "admin_pa@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "sys_pa@example.com", password: "password", role: :system_admin)

    StoreMembership.create!(store: @store1, user: @store_admin, membership_role: :admin)
  end

  test "store_admin can access own payout_account edit" do
    sign_in @store_admin, scope: :user

    post admin_current_store_path, params: { store_id: @store1.id }
    assert_response :redirect

    get edit_admin_payout_account_path
    assert_response :success
  end

  test "store_admin cannot select other store for payout_account edit" do
    sign_in @store_admin, scope: :user

    post admin_current_store_path, params: { store_id: @store2.id, return_to_key: "payout_account_edit" }
    assert_response :redirect
    assert_redirected_to admin_stores_path
    follow_redirect!
    assert_response :success
    assert_match "選択できない店舗です", response.body
  end

  test "system_admin can access selected store payout_account edit" do
    sign_in @system_admin, scope: :user

    post admin_current_store_path, params: { store_id: @store2.id }
    assert_response :redirect

    get edit_admin_payout_account_path
    assert_response :success
  end

  test "update creates new record and keeps active only one (old becomes inactive)" do
    sign_in @store_admin, scope: :user

    old = StorePayoutAccount.create!(
      store: @store1,
      payout_method: :manual_bank,
      status: :active,
      bank_code: "0001",
      branch_code: "001",
      account_type: :ordinary,
      account_number: "1234567",
      account_holder_kana: "テスト"
    )

    post admin_current_store_path, params: { store_id: @store1.id }
    assert_response :redirect

    patch admin_payout_account_path, params: {
      store_payout_account: {
        bank_code: "0005",
        branch_code: "123",
        account_type: "current",
        account_number: "7654321",
        account_holder_kana: "テストカナ"
      }
    }

    assert_response :redirect
    assert_redirected_to edit_admin_payout_account_path

    @store1.reload
    assert_equal 1, @store1.store_payout_accounts.active.count
    assert_equal 1, @store1.store_payout_accounts.inactive.count
    assert_equal "inactive", old.reload.status
  end

  test "dashboard shows unconfigured badge when payout account is missing" do
    sign_in @store_admin, scope: :user

    post admin_current_store_path, params: { store_id: @store1.id }
    follow_redirect!
    assert_response :success

    get dashboard_path
    assert_response :success
    assert_select "span.badge", text: "未設定"
  end

  test "admin store edit does not show payout account section badge anymore" do
    sign_in @store_admin, scope: :user

    get edit_admin_store_path(@store1)
    assert_response :success
    assert_select "span.badge", text: "未設定", count: 0
    assert_no_match(/精算・振込設定/, response.body)
  end

  test "account number is not fully displayed on edit screen (only last4)" do
    sign_in @store_admin, scope: :user

    StorePayoutAccount.create!(
      store: @store1,
      payout_method: :manual_bank,
      status: :active,
      bank_code: "0001",
      branch_code: "001",
      account_type: :ordinary,
      account_number: "1234567",
      account_holder_kana: "テスト"
    )

    post admin_current_store_path, params: { store_id: @store1.id }
    assert_response :redirect

    get edit_admin_payout_account_path
    assert_response :success

    assert_no_match(/1234567/, response.body)
    assert_match(/4567/, response.body)
  end

  test "update can create jp_bank payout account with converted transfer fields" do
    sign_in @store_admin, scope: :user

    post admin_current_store_path, params: { store_id: @store1.id }
    assert_response :redirect

    patch admin_payout_account_path, params: {
      store_payout_account: {
        input_account_kind: "jp_bank",
        jp_bank_symbol: "11940",
        jp_bank_number: "12345671",
        account_holder_kana: "テストカナ"
      }
    }

    assert_response :redirect
    assert_redirected_to edit_admin_payout_account_path

    account = @store1.store_payout_accounts.active.last
    assert_equal "jp_bank", account.input_account_kind
    assert_equal "11940", account.jp_bank_symbol
    assert_equal "12345671", account.jp_bank_number
    assert_equal "9900", account.bank_code
    assert_equal "198", account.branch_code
    assert_equal "ordinary", account.account_type
    assert_equal "1234567", account.account_number
  end
end
