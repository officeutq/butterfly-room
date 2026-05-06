# frozen_string_literal: true

require "test_helper"

class AdminSettlementsIndexTest < ActionDispatch::IntegrationTest
  setup do
    @store1 = Store.create!(name: "store1")
    @store2 = Store.create!(name: "store2")

    @store_admin  = User.create!(email: "admin_settlements@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "sys_settlements@example.com", password: "password", role: :system_admin)

    StoreMembership.create!(store: @store1, user: @store_admin, membership_role: :admin)

    # settlements: store1 に confirmed/exported/draft, store2 に confirmed
    @s1_confirmed = Settlement.create!(
      store: @store1,
      kind: :monthly,
      status: :confirmed,
      period_from: Time.use_zone("Asia/Tokyo") { Time.zone.today.prev_month.beginning_of_month.beginning_of_day },
      period_to: Time.use_zone("Asia/Tokyo") { Time.zone.today.beginning_of_month.beginning_of_day },
      gross_yen: 10_000,
      store_share_yen: 7_000,
      platform_fee_yen: 3_000,
      confirmed_at: Time.use_zone("Asia/Tokyo") { Time.zone.now }
    )

    @s1_draft = Settlement.create!(
      store: @store1,
      kind: :monthly,
      status: :draft,
      period_from: Time.use_zone("Asia/Tokyo") { Time.zone.today.prev_month.prev_month.beginning_of_month.beginning_of_day },
      period_to: Time.use_zone("Asia/Tokyo") { Time.zone.today.prev_month.beginning_of_month.beginning_of_day },
      gross_yen: 5_000,
      store_share_yen: 3_500,
      platform_fee_yen: 1_500
    )

    @s2_confirmed = Settlement.create!(
      store: @store2,
      kind: :monthly,
      status: :confirmed,
      period_from: Time.use_zone("Asia/Tokyo") { Time.zone.today.prev_month.beginning_of_month.beginning_of_day },
      period_to: Time.use_zone("Asia/Tokyo") { Time.zone.today.beginning_of_month.beginning_of_day },
      gross_yen: 20_000,
      store_share_yen: 14_000,
      platform_fee_yen: 6_000,
      confirmed_at: Time.use_zone("Asia/Tokyo") { Time.zone.now }
    )
  end

  test "store_admin can reach /admin/settlements without explicit current_store (fallback membership)" do
    sign_in @store_admin, scope: :user

    get admin_settlements_path
    assert_response :success

    # 画面が出ることだけ確認（詳細な中身は別テストで）
    assert_select "h1", text: "精算（予定・履歴）"
  end

  test "store_admin sees only current_store settlements and hides draft" do
    sign_in @store_admin, scope: :user

    post admin_current_store_path, params: { store_id: @store1.id }
    follow_redirect!
    assert_response :success

    get admin_settlements_path
    assert_response :success

    assert_select "h1", text: "精算（予定・履歴）"

    # テーブルではなく、精算履歴カードへのリンクが出る
    assert_select "a[href='#{admin_settlement_path(@s1_confirmed)}']", minimum: 1

    # draft は出さない
    assert_select "a[href='#{admin_settlement_path(@s1_draft)}']", count: 0
    assert_select "*", text: "未確定", count: 0
    refute_includes response.body, "draft"

    # 他店舗（store2）は出さない
    assert_select "a[href='#{admin_settlement_path(@s2_confirmed)}']", count: 0
    assert_select "*", text: @store2.name, count: 0

    # 店舗向けの日本語ステータスが出る
    assert_includes response.body, "確定済み"

    # 禁止ワードを含めない（簡易）
    body = response.body
    refute_includes body, "残高"
    refute_includes body, "引出"
    refute_includes body, "出金"
    refute_includes body, "ウォレット"
    refute_includes body, "預り金"
    refute_includes body, "いつでも受け取れる"
  end

  test "system_admin can view /admin/settlements with selected store and sees store-facing page" do
    sign_in @system_admin, scope: :user

    post admin_current_store_path, params: { store_id: @store2.id }
    follow_redirect!
    assert_response :success

    get admin_settlements_path
    assert_response :success

    assert_select "h1", text: "精算（予定・履歴）"

    # current_store（store2）の settlement のみ表示する
    assert_select "a[href='#{admin_settlement_path(@s2_confirmed)}']", minimum: 1
    assert_select "a[href='#{admin_settlement_path(@s1_confirmed)}']", count: 0
    assert_select "a[href='#{admin_settlement_path(@s1_draft)}']", count: 0
  end
end
