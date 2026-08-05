# frozen_string_literal: true

require "test_helper"

module Stores
  class RegisterStoreAdminTest < ActiveSupport::TestCase
    test "creates default drink_items and no booth when store registration succeeds" do
      rc = ReferralCode.create!(
        code: "STORE-REG-OK",
        enabled: true,
        expires_at: 1.day.from_now
      )

      result = RegisterStoreAdmin.call!(
        store_name: "テスト店舗",
        email: "store_registration_test@example.com",
        password: "password",
        referral_code: rc.code
      )

      store = result.store
      drink_items = store.drink_items.order(:position)
      booths = store.booths.order(:id)

      assert_not store.published?
      assert_equal 6, drink_items.count

      assert_equal [ "ドリンク（大）", "ドリンク（中）", "ドリンク（小）", "オリジナルシャンパン", "エンジェル", "ショット" ],
                   drink_items.pluck(:name)

      assert_equal [ 5000, 3000, 1000, 30000, 150000, 1000 ],
                   drink_items.pluck(:price_points)

      assert_equal [ 1, 2, 3, 4, 5, 6 ],
                   drink_items.pluck(:position)

      assert_equal [ true, true, true, true, true, true ],
                   drink_items.pluck(:enabled)

      assert_equal [ "mug", "mug", "mug", "champagne", "angel", "cocktail" ],
                   drink_items.pluck(:icon_key)

      assert_equal 0, booths.count
    end

    test "defaults blank referral code to 0000" do
      default_referral_code = ReferralCode.create!(
        code: RegisterStoreAdmin::DEFAULT_REFERRAL_CODE,
        enabled: true,
        expires_at: 1.day.from_now
      )

      result = RegisterStoreAdmin.call!(
        store_name: "デフォルト紹介コード店舗",
        email: "store_registration_default_ref@example.com",
        password: "password",
        referral_code: ""
      )

      assert_equal default_referral_code, result.store.referral_code
    end

    test "rolls back store, user, membership, and drink_items when default drink_item creation fails" do
      rc = ReferralCode.create!(
        code: "STORE-REG-NG",
        enabled: true,
        expires_at: 1.day.from_now
      )

      service = RegisterStoreAdmin.new(
        store_name: "ロールバック確認店舗",
        email: "store_registration_rollback@example.com",
        password: "password",
        referral_code: rc.code
      )

      invalid_items = [
        {
          "name" => "不正ドリンク",
          "price_points" => 1000,
          "position" => 1,
          "enabled" => true,
          "icon_key" => "invalid_icon"
        }
      ]

      original_method = RegistrationDefaults.method(:default_drink_item_attributes)
      RegistrationDefaults.define_singleton_method(:default_drink_item_attributes) { invalid_items }

      begin
        assert_no_difference [ "Store.count", "User.count", "StoreMembership.count", "DrinkItem.count", "Booth.count" ] do
          assert_raises ActiveRecord::RecordInvalid do
            service.call!
          end
        end
      ensure
        RegistrationDefaults.define_singleton_method(:default_drink_item_attributes, original_method)
      end
    end
  end
end
