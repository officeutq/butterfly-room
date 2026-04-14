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
    assert_includes spa.errors.details[:bank_code], { error: :blank }
    assert_includes spa.errors.details[:branch_code], { error: :blank }
    assert_includes spa.errors.details[:account_type], { error: :blank }
    assert_includes spa.errors.details[:account_number], { error: :blank }
    assert_includes spa.errors.details[:account_holder_kana], { error: :blank }
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
    assert spa.errors.details[:bank_code].any? { |detail| detail[:error] == :invalid }
    assert spa.errors.details[:branch_code].any? { |detail| detail[:error] == :invalid }
    assert spa.errors.details[:account_number].any? { |detail| detail[:error] == :invalid }
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
    assert_includes spa.errors.details[:stripe_account_id], { error: :blank }

    spa.stripe_account_id = "acct_123"
    assert spa.valid?
  end
end
