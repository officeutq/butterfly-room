# frozen_string_literal: true

require "test_helper"

module Stores
  class RegisterStoreAdminTest < ActiveSupport::TestCase
    test "creates default drink_items when store registration succeeds" do
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

      service.singleton_class.define_method(:load_default_drink_items_attributes) do
        invalid_items
      end

      assert_no_difference [ "Store.count", "User.count", "StoreMembership.count", "DrinkItem.count" ] do
        assert_raises ActiveRecord::RecordInvalid do
          service.call!
        end
      end
    end
  end
end
