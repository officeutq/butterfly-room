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

    get edit_admin_store_payout_account_path(@store1)
    assert_response :success
  end

  test "store_admin cannot access other store payout_account edit (403)" do
    sign_in @store_admin, scope: :user

    get edit_admin_store_payout_account_path(@store2)
    assert_response :forbidden
  end

  test "system_admin can access any store payout_account edit" do
    sign_in @system_admin, scope: :user

    get edit_admin_store_payout_account_path(@store2)
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

    patch admin_store_payout_account_path(@store1), params: {
      store_payout_account: {
        bank_code: "0005",
        branch_code: "123",
        account_type: "current",
        account_number: "7654321",
        account_holder_kana: "テストカナ"
      }
    }

    assert_response :redirect
    assert_redirected_to edit_admin_store_payout_account_path(@store1)

    @store1.reload
    assert_equal 1, @store1.store_payout_accounts.active.count
    assert_equal 1, @store1.store_payout_accounts.inactive.count
    assert_equal "inactive", old.reload.status
  end

  test "dashboard shows unconfigured badge when payout account is missing" do
    sign_in @store_admin, scope: :user

    # current_store を store1 に
    post admin_current_store_path, params: { store_id: @store1.id }
    follow_redirect!
    assert_response :success

    get dashboard_path
    assert_response :success
    assert_select "span.badge", text: "未設定"
  end

  test "admin store edit shows unconfigured badge when payout account is missing" do
    sign_in @store_admin, scope: :user

    get edit_admin_store_path(@store1)
    assert_response :success
    assert_select "span.badge", text: "未設定"
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

    get edit_admin_store_payout_account_path(@store1)
    assert_response :success

    # フル表示は禁止
    assert_no_match(/1234567/, response.body)
    # 下4桁は表示されてよい
    assert_match(/4567/, response.body)
  end
end
