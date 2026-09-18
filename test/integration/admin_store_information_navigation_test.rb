# frozen_string_literal: true

require "test_helper"

class AdminStoreInformationNavigationTest < ActionDispatch::IntegrationTest
  setup do
    @a = Store.create!(name: "店舗A", published: true, onboarding_step: :completed)
    @b = Store.create!(name: "店舗B", published: false, onboarding_step: :completed)
    @admin = User.create!(email: "store-navigation@example.com", password: "password", role: :store_admin)
    [ @a, @b ].each { |store| StoreMembership.create!(store: store, user: @admin, membership_role: :admin) }
    sign_in @admin
    post admin_current_store_path, params: { store_id: @a.id }
  end

  %i[store_admin system_admin].each do |role|
    test "#{role}: information and edits follow explicit store switching without creating broadcasts" do
      @admin.update!(role: role)
      a_booth = Booth.create!(store: @a, name: "Aのみのブース", status: :standby)
      prepared = StreamSession.create!(store: @a, booth: a_booth, started_by_cast_user: @admin,
        started_at: Time.current, status: :live)
      a_booth.update!(current_stream_session: prepared)
      before = [ a_booth.attributes, prepared.attributes ]
      assert_no_difference "StreamSession.count" do
        get admin_store_path(@a)
        assert_response :ok
        assert_select "a[href=?]", edit_admin_store_path(@a), text: "店舗情報を編集"
        assert_select "a[href=?]", admin_drink_items_path(**options(@a)), text: "ドリンクメニューを編集"
        assert_select "a[href=?]", edit_admin_payout_account_path(**options(@a)), text: "振込先口座を編集"

        post admin_current_store_path, params: { store_id: @b.id, return_to: admin_store_path(@a) }, as: :json
        assert_equal admin_store_path(@b), response.parsed_body.fetch("redirect_url")
        get admin_store_path(@b)
        assert_response :ok
        assert_equal @b.id, session[:current_store_id]
        assert_nil session[:current_booth_id]
        assert_select "a[href=?]", admin_drink_items_path(**options(@b))
        get dashboard_path
        assert_nil session[:current_booth_id]

        [ @a, @b ].each do |store|
          post admin_current_store_path, params: { store_id: store.id, return_to_key: "store_show" }
          assert_redirected_to admin_store_path(store)
          get edit_admin_store_path(store)
          assert_select "a.store-edit__back[href=?]", admin_store_path(store)
        end
      end
      assert_equal before, [ a_booth.reload.attributes, prepared.reload.attributes ]
    end

    test "#{role}: dashboard groups entry points and displays only the selected account badge" do
      @admin.update!(role: role)
      get dashboard_path
      assert_select "a[href=?] [data-onboarding-target-element='store-information-card']", admin_store_path(@a)
      assert_select ".card-title .badge", text: "振込先口座未設定", count: 1
      [ "店舗設定編集", "ドリンクメニュー", "振込先口座設定" ].each do |title|
        assert_select ".card-title", text: title, count: 0
      end
      assert_select ".card-title", text: "店舗を選択", count: 1
      create_account(@b)
      post admin_current_store_path, params: { store_id: @b.id }
      get dashboard_path
      assert_select ".card-title .badge", text: "振込先口座未設定", count: 0
      assert_select "a[href=?] [data-onboarding-target-element='store-information-card']", admin_store_path(@b)
      get store_path(@a)
      assert_select ".store-show a[href^='/admin/stores/']", count: 0
    end
  end

  test "old A editing links never open B data after another tab changes selection" do
    create_account(@b)
    @b.drink_items.create!(name: "B限定メニュー", price_points: 400)
    post admin_current_store_path, params: { store_id: @b.id }
    [ edit_admin_store_path(@a), admin_drink_items_path(**options(@a)), edit_admin_payout_account_path(**options(@a)) ].each do |path|
      get path
      assert_response :conflict
      refute_includes response.body, "B限定メニュー"
      refute_includes response.body, "****4567"
      assert_equal @b.id, session[:current_store_id]
    end
  end

  test "header switching replaces editing store parameters and drops the previous drink edit id" do
    [ [ admin_drink_items_path(editing_id: 999, **options(@a)), admin_drink_items_path(**options(@b)) ],
      [ edit_admin_payout_account_path(**options(@a)), edit_admin_payout_account_path(**options(@b)) ],
      [ edit_admin_store_path(@a, return_to: "store_detail"), edit_admin_store_path(@b) ] ].each do |from, destination|
      post admin_current_store_path, params: { store_id: @b.id, return_to: from }, as: :json
      assert_response :ok
      assert_equal destination, response.parsed_body.fetch("redirect_url")
      get destination
      assert_response :ok
    end
  end

  test "unselected multiple stores lead to the chosen information URL and never borrow an account badge" do
    delete destroy_user_session_path
    sign_in @admin
    get dashboard_path
    assert_nil session[:current_store_id]
    assert_select ".card-title .badge", text: "振込先口座未設定", count: 0
    path = select_modal_admin_stores_path(return_to_key: "store_show", required: 1)
    assert_select "a[href=?][data-turbo-frame=modal][data-turbo-prefetch=false]", path
    get admin_store_path(@a)
    assert_redirected_to select_modal_admin_stores_path(return_to: admin_store_path(@a), required: 1)
    get response.location
    follow_redirect! if response.redirect?
    assert_response :ok
    post admin_current_store_path, params: { store_id: @b.id, return_to: admin_store_path(@a) }
    assert_redirected_to admin_store_path(@b)
  end

  test "zero stores show the existing explanation and one store bypasses selection" do
    StoreMembership.where(user: @admin).delete_all
    get select_modal_admin_stores_path(return_to_key: "store_show", required: 1)
    assert_response :conflict
    assert_includes response.body, "管理可能な店舗がありません"
    StoreMembership.create!(store: @b, user: @admin, membership_role: :admin)
    get select_modal_admin_stores_path(return_to_key: "store_show", required: 1)
    assert_redirected_to admin_store_path(@b)
    get dashboard_path
    assert_select ".card-title", text: "店舗を選択", count: 0
  end

  test "prefetching the unset information entry does not select a store" do
    delete destroy_user_session_path
    sign_in @admin
    get select_modal_admin_stores_path(return_to_key: "store_show", required: 1), headers: { "Sec-Purpose" => "prefetch" }
    assert_response :no_content
    assert_nil session[:current_store_id]
  end

  test "drink creation validation and retry preserve the store destination" do
    get admin_drink_items_path(**options(@a))
    assert_select "a[href=?]", admin_store_path(@a), text: "店舗情報へ戻る"
    post admin_drink_items_path, params: options(@a).merge(drink_item: { name: "", price_points: 500 })
    assert_response :unprocessable_entity
    assert_select "input[name=return_to][value=store_information]"
    assert_select "input[name=selection_store_id][value=?]", @a.id.to_s
    post admin_drink_items_path, params: options(@a).merge(drink_item: { name: "新メニュー", price_points: 500 })
    assert_redirected_to admin_store_path(@a)
    assert_equal @a.id, DrinkItem.find_by!(name: "新メニュー").store_id
  end

  test "drink editing cancellation and disabling stay on the target menu while save returns to information" do
    item = @a.drink_items.create!(name: "メニュー", price_points: 500)
    get admin_drink_items_path(editing_id: item.id, **options(@a))
    assert_select "a[href=?]", admin_drink_items_path(**options(@a)), text: "キャンセル"
    patch admin_drink_item_path(item), params: options(@a).merge(drink_item: { name: "", price_points: 600 })
    assert_response :unprocessable_entity
    assert_select "input[name=return_to][value=store_information]"
    patch admin_drink_item_path(item), params: options(@a).merge(drink_item: { name: "更新メニュー" })
    assert_redirected_to admin_store_path(@a)
    patch admin_drink_item_path(item), params: options(@a).merge(menu_action: "toggle", drink_item: { enabled: false })
    assert_redirected_to admin_drink_items_path(**options(@a))
    follow_redirect!
    assert_select "a[href=?]", admin_store_path(@a), text: "店舗情報へ戻る"
    delete admin_drink_item_path(item), params: options(@a)
    assert_redirected_to admin_drink_items_path(**options(@a))
  end

  test "stale drink and account forms retain A input and cannot mutate A or B" do
    item = @a.drink_items.create!(name: "Aメニュー", price_points: 500)
    post admin_current_store_path, params: { store_id: @b.id }
    assert_no_difference [ "DrinkItem.count", "StorePayoutAccount.count" ] do
      post admin_drink_items_path, params: options(@a).merge(drink_item: { name: "未保存", price_points: 700 })
      assert_response :conflict
      assert_select "input[name='drink_item[name]'][value='未保存']"
      assert_select "input[name=selection_store_id][value=?]", @a.id.to_s
      assert_select "input[name=return_to][value=store_information]"
      patch admin_drink_item_path(item), params: options(@a).merge(drink_item: { name: "更新未保存" })
      assert_response :conflict
      assert_equal "Aメニュー", item.reload.name
      patch admin_payout_account_path, params: options(@a).merge(store_payout_account: account_attributes)
      assert_response :conflict
      assert_select "input[name=selection_store_id][value=?]", @a.id.to_s
      assert_select "input[name=return_to][value=store_information]"
      assert_select "input[name='store_payout_account[account_holder_kana]'][value='テスト']"
      assert_select "a[href=?]", admin_store_path(@a), text: "戻る"
    end
    assert_equal @b.id, session[:current_store_id]
  end

  test "account validation preserves input destination and active history until successful save" do
    old = create_account(@a)
    get edit_admin_payout_account_path(**options(@a))
    assert_select "a[href=?]", admin_store_path(@a), text: "戻る"
    patch admin_payout_account_path, params: options(@a).merge(store_payout_account: account_attributes.merge(bank_code: ""))
    assert_response :unprocessable_entity
    assert_select "input[name=return_to][value=store_information]"
    assert_select "input[name='store_payout_account[account_holder_kana]'][value='テスト']"
    assert old.reload.active?
    patch admin_payout_account_path, params: options(@a).merge(store_payout_account: account_attributes)
    assert_redirected_to admin_store_path(@a)
    assert old.reload.inactive?
    assert_equal 1, @a.store_payout_accounts.active.count
  end

  test "explicit edit targets reject missing or revoked membership before exposing settings" do
    StoreMembership.find_by!(store: @a, user: @admin).destroy!
    [ @a.id, 0 ].each do |id|
      [ admin_drink_items_path(selection_store_id: id, return_to: "store_information"),
        edit_admin_payout_account_path(selection_store_id: id, return_to: "store_information") ].each do |path|
        get path
        assert_response :forbidden
      end
    end
  end

  test "onboarding guides information then editing but only saving completes it" do
    @a.update!(onboarding_step: :go_dashboard_for_drinks)
    get dashboard_path
    assert_equal "setup_drinks", @a.reload.onboarding_step
    assert_select "[data-onboarding-target-element='store-information-card']", count: 1
    2.times do
      get admin_store_path(@a)
      assert_select "[data-onboarding-step-value=setup_drinks]"
      assert_select "a[data-onboarding-target-element='store-drinks-edit']", count: 1
      assert_equal "setup_drinks", @a.reload.onboarding_step
    end
    get admin_drink_items_path(**options(@a))
    assert_select "[data-onboarding-target-element='create-drink-card']"
    assert_equal "setup_drinks", @a.reload.onboarding_step
    post admin_drink_items_path, params: options(@a).merge(drink_item: { name: "案内完了", price_points: 500 })
    assert_redirected_to admin_store_path(@a)
    follow_redirect!
    assert_equal "completed", @a.reload.onboarding_step
    assert_select "[data-controller~=onboarding]", count: 0
    [ :skipped, :completed ].each do |step|
      @a.update!(onboarding_step: step)
      get admin_store_path(@a)
      assert_select "[data-controller~=onboarding]", count: 0
      assert_select "a[data-onboarding-target-element='store-drinks-edit']", count: 1
    end
  end

  private

  def options(store)
    { selection_store_id: store.id, return_to: "store_information" }
  end

  def account_attributes
    { bank_code: "0001", branch_code: "001", account_type: "ordinary", account_number: "1234567", account_holder_kana: "テスト" }
  end

  def create_account(store)
    StorePayoutAccount.create!(account_attributes.merge(store: store, payout_method: :manual_bank, status: :active))
  end
end
