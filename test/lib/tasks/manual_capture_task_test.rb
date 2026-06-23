# frozen_string_literal: true

require "test_helper"
require "rake"

class ManualCaptureTaskTest < ActiveSupport::TestCase
  TASK_NAME = "manual_capture:prepare"

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?(TASK_NAME)
    Rake::Task[TASK_NAME].reenable
  end

  test "prepare creates screenshot data and is idempotent" do
    Rake::Task[TASK_NAME].invoke

    system_admin = User.find_by!(email: "manual+system_admin@example.test")
    store_admin = User.find_by!(email: "manual+store_admin@example.test")
    cast = User.find_by!(email: "manual+cast@example.test")
    customer = User.find_by!(email: "manual+customer@example.test")
    store = Store.find_by!(name: "マニュアル撮影用店舗")
    booth = Booth.find_by!(store: store, name: "マニュアル撮影用ブース")

    assert system_admin.system_admin?
    assert store_admin.store_admin?
    assert cast.cast?
    assert customer.customer?
    assert customer.phone_verified?
    assert_equal "MANUAL-CAPTURE-LOCAL", store.referral_code.code
    assert_equal "arn:aws:ivsrealtime:ap-northeast-1:000000000000:stage/manual-capture-local", booth.ivs_stage_arn
    assert StoreMembership.exists?(store: store, user: store_admin, membership_role: :admin)
    assert StoreMembership.exists?(store: store, user: cast, membership_role: :cast)
    assert BoothCast.exists?(booth: booth, cast_user: cast)
    assert_equal 6, store.drink_items.count
    assert_equal 100_000, customer.wallet.available_points

    Rake::Task[TASK_NAME].reenable

    assert_no_difference [
      "User.count",
      "ReferralCode.count",
      "Store.count",
      "StoreMembership.count",
      "Booth.count",
      "BoothCast.count",
      "DrinkItem.count",
      "Wallet.count",
      "WalletTransaction.count"
    ] do
      Rake::Task[TASK_NAME].invoke
    end
  end

  test "data builder is disabled in production" do
    production_env = ActiveSupport::StringInquirer.new("production")

    assert_raises RuntimeError do
      ManualCapture::DataBuilder.new(rails_env: production_env).call!
    end
  end
end
