# frozen_string_literal: true

require "test_helper"

class AdminStoreInformationTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "管理対象店舗", published: true, description: "店舗の紹介文", area: "渋谷",
      business_type: :girls_bar, phone_number: "03-1111-2222", business_hours: "19:00〜翌1:00",
      website_url: "https://example.com/shop", x_url: "https://x.com/example")
    @other_store = Store.create!(name: "別の店舗", published: false)
    @admin = User.create!(email: "store-info-admin@example.com", password: "password", role: :store_admin)
    @system_admin = User.create!(email: "store-info-system@example.com", password: "password", role: :system_admin)
    @membership = StoreMembership.create!(store: @store, user: @admin, membership_role: :admin)
  end

  test "authorized administrators can read selected published and unpublished stores" do
    [ @admin, @system_admin ].each do |actor|
      sign_in actor, scope: :user
      post admin_current_store_path, params: { store_id: @store.id }
      [ true, false ].each do |published|
        @store.update!(published: published)
        get admin_store_path(@store)
        assert_response :success
        assert_select "h1", text: @store.name
        assert_select ".store-show-header .badge", text: published ? "公開中" : "非公開"
        assert_select "#store-basic-information-title", text: "店舗基本情報"
        assert_select "#store-drink-menu-title", text: "ドリンクメニュー"
        assert_select "#store-payout-account-title", text: "振込先口座"
      end
      sign_out actor
    end
  end

  test "guest customer and cast cannot read management information" do
    get admin_store_path(@store)
    assert_redirected_to new_user_session_path
    %i[customer cast].each do |role|
      user = User.create!(email: "store-info-#{role}@example.com", password: "password", role: role)
      StoreMembership.create!(store: @store, user: user, membership_role: :cast) if role == :cast
      sign_in user, scope: :user
      get admin_store_path(@store)
      assert_response :forbidden
      assert_select "#store-payout-account-title", count: 0
      sign_out user
    end
  end

  test "store admin cannot read another store even with cast membership there" do
    StoreMembership.create!(store: @other_store, user: @admin, membership_role: :cast)
    sign_in @admin, scope: :user
    get admin_store_path(@other_store)
    assert_response :forbidden
    assert_select "#store-payout-account-title", count: 0
    assert_equal @store.id, session[:current_store_id]
  end

  test "system admin can read a selected store without membership" do
    sign_in @system_admin, scope: :user
    post admin_current_store_path, params: { store_id: @other_store.id }
    get admin_store_path(@other_store)
    assert_response :success
    assert_select "h1", text: @other_store.name
    assert_select ".store-show-header .badge", text: "非公開"
  end

  test "lost management membership is rejected before rendering information" do
    sign_in @admin, scope: :user
    get admin_store_path(@store)
    assert_response :success
    @membership.destroy!
    get admin_store_path(@store)
    assert_response :forbidden
    assert_select "#store-payout-account-title", count: 0
  end

  test "nonexistent store is not replaced by the selected store" do
    sign_in @admin, scope: :user
    get admin_store_path(Store.maximum(:id) + 1)
    assert_response :not_found
    assert_select "#store-payout-account-title", count: 0
    assert_equal @store.id, session[:current_store_id]
  end

  test "authorized but unselected URL does not switch or display another store" do
    StoreMembership.create!(store: @other_store, user: @admin, membership_role: :admin)
    sign_in @admin, scope: :user
    post admin_current_store_path, params: { store_id: @other_store.id }
    get admin_store_path(@store)
    assert_response :conflict
    assert_includes response.body, "対象の店舗をヘッダーから選択してください"
    assert_select "#store-payout-account-title", count: 0
    assert_equal @other_store.id, session[:current_store_id]
  end

  test "multiple unselected stores use the existing required selection without selecting URL target" do
    StoreMembership.create!(store: @other_store, user: @admin, membership_role: :admin)
    sign_in @admin, scope: :user
    get admin_store_path(@store)
    assert_redirected_to select_modal_admin_stores_path(return_to: admin_store_path(@store), required: 1)
    assert_nil session[:current_store_id]
    assert_select "#store-payout-account-title", count: 0
  end

  test "basic information reuses public presentation including safe URLs and uploaded image" do
    @store.update_column(:address, "東京都渋谷区の店舗住所")
    @store.update!(instagram_url: "https://www.instagram.com/example", tiktok_url: "https://www.tiktok.com/@example",
      youtube_url: "https://www.youtube.com/@example")
    attach_image(@store.thumbnail)
    sign_in @admin, scope: :user
    get admin_store_path(@store)
    assert_response :success
    [ @store.area, "ガールズバー", @store.address, @store.phone_number, @store.business_hours, @store.description ].each do |value|
      assert_includes response.body, value
    end
    assert_select "img.store-show-hero-image[alt=?]", "#{@store.name}の店舗画像"
    assert_select "a[href=?]", @store.website_url
    assert_select ".store-show-sns-link", count: 4
    assert_select "a[href=?]", "https://www.google.com/maps/search/?api=1&query=#{ERB::Util.url_encode(@store.address)}"

    @store.update!(website_url: "javascript:alert(1)", x_url: "javascript:alert(2)")
    get admin_store_path(@store)
    assert_response :success
    assert_select ".store-show a[href^='javascript:']", count: 0
  end

  test "empty information has image placeholder and unset messages without edit forms" do
    sign_in @system_admin, scope: :user
    post admin_current_store_path, params: { store_id: @other_store.id }
    get admin_store_path(@other_store)
    assert_response :success
    assert_select ".store-show-hero-placeholder img"
    assert_select ".store-show-info-value", text: "-", minimum: 6
    assert_includes response.body, "ドリンクメニューはまだ登録されていません。"
    assert_select "section[aria-labelledby='store-payout-account-title'] p", text: "未設定"
    assert_select ".store-show form, .store-show input", count: 0
    assert_select ".store-show-booths", count: 0
  end

  test "drink menu includes enabled and disabled items in existing order with images and prices" do
    last = @store.drink_items.create!(name: "無効メニュー", position: 2, price_points: 2500, enabled: false)
    first = @store.drink_items.create!(name: "画像付きメニュー", position: 1, price_points: 1200, enabled: true)
    second = @store.drink_items.create!(name: "既存アイコン", position: 1, price_points: 500, icon_key: "mug")
    attach_image(first.custom_icon)
    @other_store.drink_items.create!(name: "他店舗の限定メニュー", price_points: 100, enabled: false)
    sign_in @admin, scope: :user
    get admin_store_path(@store)
    assert_response :success
    assert_select "[data-drink-item-id]" do |rows|
      assert_equal [ first.id, second.id, last.id ], rows.map { |row| row["data-drink-item-id"].to_i }
    end
    assert_select "[data-drink-item-id='#{first.id}'] img"
    assert_select "[data-drink-item-id='#{second.id}'] img[src*='drink_mug']"
    assert_select "[data-drink-item-id='#{last.id}'] .badge", text: "無効"
    assert_select "[data-drink-item-id='#{first.id}'] .badge", text: "有効"
    assert_includes response.body, "1,200 pt"
    refute_includes response.body, "他店舗の限定メニュー"
  end

  test "only active bank account is shown and full account numbers never enter HTML" do
    create_bank_account(status: :inactive, account_number: "9345678", account_holder_kana: "カコノコウザ")
    account = create_bank_account
    create_bank_account(store: @other_store, account_number: "7654321", account_holder_kana: "ベツテンポ")
    sign_in @admin, scope: :user
    get admin_store_path(@store)
    assert_response :success
    assert_select "section[aria-labelledby='store-payout-account-title']" do
      assert_select ".badge", text: "設定済み"
      assert_select "dd", text: "銀行口座"
      assert_select "dd", text: "****3467"
      assert_select "dd", text: account.account_holder_kana
    end
    %w[8123467 9345678 7654321 カコノコウザ ベツテンポ].each { |value| refute_includes response.body, value }
  end

  test "jp bank uses the existing symbol and masked number without transfer number exposure" do
    account = StorePayoutAccount.create!(store: @store, payout_method: :manual_bank, status: :active,
      input_account_kind: :jp_bank, jp_bank_symbol: "11940", jp_bank_number: "12345671", account_holder_kana: "ユウチョ")
    sign_in @admin, scope: :user
    get admin_store_path(@store)
    assert_response :success
    assert_select "dd", text: "ゆうちょ銀行"
    assert_select "dd", text: "11940"
    assert_select "dd", text: "****5671"
    refute_includes response.body, account.jp_bank_number
    refute_includes response.body, account.account_number
  end

  test "public store details never include private menu or payout information" do
    account = create_bank_account
    @store.drink_items.create!(name: "管理者だけの無効メニュー", price_points: 500, enabled: false)
    sign_in @admin, scope: :user
    get store_path(@store)
    assert_response :success
    assert_select "a.store-show-edit", count: 1
    assert_select "#store-payout-account-title, #store-drink-menu-title", count: 0
    [ account.account_number, account.account_holder_kana, "****3467", "管理者だけの無効メニュー" ].each do |value|
      refute_includes response.body, value
    end
    @store.update!(published: false)
    get store_path(@store)
    assert_response :not_found
  end

  test "viewing information changes neither stored business data nor prepared broadcast" do
    create_bank_account
    @store.drink_items.create!(name: "既存メニュー", price_points: 500)
    booth = Booth.create!(store: @store, name: "準備中のブース", status: :standby)
    broadcast = StreamSession.create!(store: @store, booth: booth, started_by_cast_user: @admin,
      status: :live, started_at: Time.current)
    booth.update!(current_stream_session: broadcast)
    records = [ @store, @other_store, booth, broadcast, *@store.drink_items, *@store.store_payout_accounts ]
    before = records.map(&:attributes)
    sign_in @admin, scope: :user
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      assert_no_difference [ "StreamSession.count", "StreamPublisherConnection.count", "StorePayoutAccount.count", "StoreLedgerEntry.count" ] do
        get admin_store_path(@store)
      end
    end
    assert_response :success
    assert_equal before, records.map { |record| record.reload.attributes }
    assert_equal booth.id, session[:current_booth_id]
  end

  private

  def create_bank_account(**attributes)
    StorePayoutAccount.create!({ store: @store, payout_method: :manual_bank, status: :active,
      bank_code: "0001", branch_code: "001", account_type: :ordinary,
      account_number: "8123467", account_holder_kana: "ゲンザイノコウザ" }.merge(attributes))
  end

  def attach_image(attachment)
    File.open(file_fixture("thumb.png"), "rb") do |io|
      attachment.attach(io: io, filename: "thumb.png", content_type: "image/png")
    end
  end
end
