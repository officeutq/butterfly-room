# frozen_string_literal: true

require "test_helper"

module Stores
  class RegisterProxyStoreTest < ActiveSupport::TestCase
    setup do
      @referral_code = ReferralCode.create!(code: "PROXY-STORE", enabled: true, expires_at: 1.day.from_now)
      @actor = User.create!(email: "proxy-store-actor@example.com", password: "password", role: :store_admin)
      @support_company = Store.create!(name: "Support Company", sales_support_company: true)
      StoreMembership.create!(store: @support_company, user: @actor, membership_role: :admin)
    end

    test "creates an unpublished store with defaults and actor membership without creating a user" do
      assert_no_difference "User.count" do
        assert_difference "Store.count", 1 do
          assert_difference "StoreMembership.count", 1 do
            assert_difference "DrinkItem.count", 6 do
              @result = RegisterProxyStore.call!(
                store_name: "Proxy Store",
                referral_code: @referral_code.code,
                actor: @actor
              )
            end
          end
        end
      end

      store = @result.store
      assert_not store.published?
      assert_not store.sales_support_company?
      assert store.onboarding_step_invite_cast?
      assert_equal @referral_code, store.referral_code
      assert_equal @actor, @result.membership.user
      assert @result.membership.admin?
    end

    test "blank referral code uses the standard code" do
      standard = ReferralCode.create!(
        code: RegistrationDefaults::DEFAULT_REFERRAL_CODE,
        enabled: true,
        expires_at: 1.day.from_now
      )

      result = RegisterProxyStore.call!(store_name: "Standard Store", referral_code: "", actor: @actor)

      assert_equal standard, result.store.referral_code
    end

    test "unauthorized actor cannot create data" do
      actor = User.create!(email: "proxy-store-denied@example.com", password: "password", role: :store_admin)

      assert_no_difference [ "Store.count", "StoreMembership.count", "DrinkItem.count" ] do
        assert_raises RegisterProxyStore::NotAuthorized do
          RegisterProxyStore.call!(store_name: "Denied", referral_code: @referral_code.code, actor: actor)
        end
      end
    end

    test "stopped actor cannot create data" do
      @actor.update!(deleted_at: Time.current)

      assert_no_difference [ "Store.count", "StoreMembership.count", "DrinkItem.count" ] do
        assert_raises RegisterProxyStore::NotAuthorized do
          RegisterProxyStore.call!(store_name: "Denied", referral_code: @referral_code.code, actor: @actor)
        end
      end
    end
  end
end
