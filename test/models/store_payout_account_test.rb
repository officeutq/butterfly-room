# frozen_string_literal: true

require "test_helper"

class StorePayoutAccountTest < ActiveSupport::TestCase
  test "active is unique per store at DB level (partial unique index)" do
    store = Store.create!(name: "store")

    StorePayoutAccount.create!(
      store: store,
      payout_method: :manual_bank,
      status: :active,
      bank_code: "0001",
      branch_code: "001",
      account_type: :ordinary,
      account_number: "0000001",
      account_holder_kana: "ﾀﾛｳ"
    )

    assert_raises(ActiveRecord::RecordNotUnique) do
      StorePayoutAccount.create!(
        store: store,
        payout_method: :manual_bank,
        status: :active,
        bank_code: "0001",
        branch_code: "001",
        account_type: :ordinary,
        account_number: "0000002",
        account_holder_kana: "ｼﾞﾛｳ"
      )
    end
  end

  test "manual_bank requires bank fields" do
    store = Store.create!(name: "store")

    spa = StorePayoutAccount.new(
      store: store,
      payout_method: :manual_bank,
      status: :active
    )

    assert_not spa.valid?
    assert_includes spa.errors[:bank_code], "can't be blank"
    assert_includes spa.errors[:branch_code], "can't be blank"
    assert_includes spa.errors[:account_type], "can't be blank"
    assert_includes spa.errors[:account_number], "can't be blank"
    assert_includes spa.errors[:account_holder_kana], "can't be blank"
  end

  test "manual_bank validates code formats and account_number length" do
    store = Store.create!(name: "store")

    spa = StorePayoutAccount.new(
      store: store,
      payout_method: :manual_bank,
      status: :active,
      bank_code: "123",         # invalid
      branch_code: "12",        # invalid
      account_type: :ordinary,
      account_number: "123456", # invalid
      account_holder_kana: "ﾀﾛｳ"
    )

    assert_not spa.valid?
    assert_includes spa.errors[:bank_code], "is invalid"
    assert_includes spa.errors[:branch_code], "is invalid"
    assert_includes spa.errors[:account_number], "is invalid"
  end

  test "stripe_connect requires stripe_account_id (future-proof)" do
    store = Store.create!(name: "store")

    spa = StorePayoutAccount.new(
      store: store,
      payout_method: :stripe_connect,
      status: :active,
      stripe_account_id: nil
    )

    assert_not spa.valid?
    assert_includes spa.errors[:stripe_account_id], "can't be blank"

    spa.stripe_account_id = "acct_123"
    assert spa.valid?
  end
end
