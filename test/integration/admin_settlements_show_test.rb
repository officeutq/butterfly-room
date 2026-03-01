# frozen_string_literal: true

require "test_helper"

class AdminSettlementsShowTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "store1")
    @store_admin = User.create!(email: "admin_settlement_show@example.com", password: "password", role: :store_admin)
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
  end

  test "store_admin cannot view draft settlement detail" do
    sign_in @store_admin, scope: :user

    post admin_current_store_path, params: { store_id: @store.id }
    follow_redirect!
    assert_response :success

    get admin_settlement_path(@draft)
    assert_response :not_found
  end
end
