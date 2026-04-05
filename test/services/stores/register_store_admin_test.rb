# frozen_string_literal: true

require "test_helper"

module Stores
  class RegisterStoreAdminTest < ActiveSupport::TestCase
    setup do
      fake_ivs_client = Object.new
      fake_ivs_client.define_singleton_method(:create_stage!) do |name:, tags: {}|
        "arn:aws:ivs:ap-northeast-1:123456789012:stage/test-stage"
      end

      Ivs::Client.factory = ->(region:) { fake_ivs_client }
    end

    teardown do
      Ivs::Client.reset_factory!
    end

    test "creates default drink_items and booth when store registration succeeds" do
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

      assert_equal 1, booths.count
      assert_equal "テスト店舗のブース", booths.first.name
      assert_equal store.id, booths.first.store_id
      assert booths.first.offline?
      assert_equal "arn:aws:ivs:ap-northeast-1:123456789012:stage/test-stage", booths.first.ivs_stage_arn
    end

    test "rolls back store, user, membership, drink_items, and booth when default drink_item creation fails" do
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

      assert_no_difference [ "Store.count", "User.count", "StoreMembership.count", "DrinkItem.count", "Booth.count" ] do
        assert_raises ActiveRecord::RecordInvalid do
          service.call!
        end
      end
    end

    test "rolls back store, user, membership, drink_items, and booth when ivs stage provisioning fails" do
      rc = ReferralCode.create!(
        code: "STORE-REG-IVS-NG",
        enabled: true,
        expires_at: 1.day.from_now
      )

      fake_ivs_client = Object.new
      fake_ivs_client.define_singleton_method(:create_stage!) do |name:, tags: {}|
        raise Aws::Errors::ServiceError.new(nil, "ivs failed")
      end

      Ivs::Client.factory = ->(region:) { fake_ivs_client }

      assert_no_difference [ "Store.count", "User.count", "StoreMembership.count", "DrinkItem.count", "Booth.count" ] do
        assert_raises Booths::ProvisionIvsStageService::StageProvisionFailed do
          RegisterStoreAdmin.call!(
            store_name: "IVS失敗店舗",
            email: "store_registration_ivs_rollback@example.com",
            password: "password",
            referral_code: rc.code
          )
        end
      end
    end
  end
end
