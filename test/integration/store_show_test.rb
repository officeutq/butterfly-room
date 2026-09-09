# frozen_string_literal: true

require "test_helper"

class StoreShowTest < ActionDispatch::IntegrationTest
  test "guest can view a published store and open booth and cast details" do
    store = Store.create!(name: "Guest Store", published: true)
    booth = Booth.create!(store: store, name: "Guest Booth", status: :offline)
    cast = User.create!(
      email: "guest-store-cast@example.com",
      password: "password",
      role: :cast,
      display_name: "Guest Store Cast"
    )
    BoothCast.create!(booth: booth, cast_user: cast)

    get store_path(store)
    assert_response :success

    assert_select "h1", text: store.name
    assert_select "a.store-show-edit", count: 0
    assert_includes @response.body, booth.name
    assert_select "form[action=?]", booth_path(booth), minimum: 2
    assert_select "a[href=?]", user_path(cast), text: cast.display_name
    assert_select "a.viewer-favorite-btn[href=?][data-turbo-frame='modal']", guest_auth_prompt_path, minimum: 4
    assert_select "#app_footer a[href=?][data-turbo-frame='modal']", guest_auth_prompt_path, count: 3
  end

  test "guest cannot view an unpublished store" do
    store = Store.create!(name: "Hidden Store", published: false)

    get store_path(store)

    assert_response :not_found
  end

  test "customer can view store show and see active booths only" do
    address = "熊本県熊本市中央区本丸1-1"
    store = Store.create!(
      name: "store",
      published: true,
      description: "Store description",
      area: "渋谷",
      business_type: :girls_bar,
      phone_number: "090-1111-2222",
      business_hours: "平日 19:00〜1:00",
      website_url: "https://officeutq.co.jp",
      x_url: "https://x.com/Butterflyve_jp",
      instagram_url: "https://www.instagram.com/butterflyve_0315/",
      tiktok_url: "https://www.tiktok.com/@aespa_official",
      youtube_url: "https://www.youtube.com/@SleepRelaxingHealingMusic"
    )
    store.update_column(:address, address)

    store.thumbnail.attach(
      io: File.open(Rails.root.join("test/fixtures/files/thumb.png")),
      filename: "thumb.png",
      content_type: "image/png"
    )

    active_booth = Booth.create!(store: store, name: "active", status: :offline)
    Booth.create!(store: store, name: "archived", status: :offline, archived_at: Time.current)

    cast = User.create!(email: "cast@example.com", password: "password", role: :cast, display_name: "Cast A")
    BoothCast.create!(booth: active_booth, cast_user: cast)

    customer = User.create!(email: "customer@example.com", password: "password", role: :customer)
    sign_in customer, scope: :user

    get store_path(store)
    assert_response :success

    assert_select "a.store-show-edit", count: 0
    assert_includes @response.body, "store"
    assert_includes @response.body, "Store description"
    assert_includes @response.body, "渋谷"
    assert_includes @response.body, "ガールズバー"
    assert_includes @response.body, "熊本県熊本市中央区本丸1-1"
    assert_includes @response.body, "090-1111-2222"
    assert_includes @response.body, "平日 19:00〜1:00"
    assert_includes @response.body, "https://officeutq.co.jp"
    assert_includes @response.body, "<img"

    encoded_address = ERB::Util.url_encode(store.address)
    assert_includes @response.body, "https://www.google.com/maps/search/?api=1&amp;query=#{encoded_address}"
    assert_includes @response.body, "https://officeutq.co.jp"
    assert_includes @response.body, "https://x.com/Butterflyve_jp"
    assert_includes @response.body, "https://www.instagram.com/butterflyve_0315/"
    assert_includes @response.body, "https://www.tiktok.com/@aespa_official"
    assert_includes @response.body, "https://www.youtube.com/@SleepRelaxingHealingMusic"

    assert_includes @response.body, "active"
    assert_includes @response.body, "Cast A"
    assert_includes @response.body, enter_booth_path(active_booth)

    refute_includes @response.body, "archived"
  end

  test "unsafe website url is not linkified" do
    store = Store.create!(
      name: "store",
      published: true,
      website_url: "javascript:alert(1)"
    )

    customer = User.create!(email: "customer2@example.com", password: "password", role: :customer)
    sign_in customer, scope: :user

    get store_path(store)
    assert_response :success

    assert_includes @response.body, "javascript:alert(1)"
    refute_includes @response.body, 'href="javascript:alert(1)"'
  end

  test "store admin sees edit only for stores they administer, independent of the selected store" do
    store = Store.create!(name: "管理店舗", published: true)
    selected_store = Store.create!(name: "選択中の管理店舗", published: true)
    other_store = Store.create!(name: "他店舗", published: true)
    admin = User.create!(email: "store-show-admin@example.com", password: "password", role: :store_admin)
    [ store, selected_store ].each do |managed_store|
      StoreMembership.create!(store: managed_store, user: admin, membership_role: :admin)
    end
    sign_in admin, scope: :user
    post admin_current_store_path, params: { store_id: selected_store.id }

    get store_path(store)

    assert_response :success
    assert_select "a.store-show-edit[href=?]", edit_admin_store_path(store, return_to: "store_detail"),
                  text: "店舗情報を編集", count: 1
    assert_equal selected_store.id, @request.session[:current_store_id].to_i

    get store_path(other_store)

    assert_response :success
    assert_select "a.store-show-edit", count: 0
  end

  test "cast membership and user role alone do not grant a store edit link" do
    store = Store.create!(name: "編集権限確認店舗", published: true)
    [ :customer, :cast, :store_admin ].each do |role|
      user = User.create!(email: "store-show-#{role}@example.com", password: "password", role:)
      membership_role = role == :store_admin ? :cast : :admin
      StoreMembership.create!(store:, user:, membership_role:)
      sign_in user, scope: :user

      get store_path(store)

      assert_response :success
      assert_select "a.store-show-edit", count: 0
    end
  end

  test "system admin sees edit without membership but unpublished details remain unavailable to operators" do
    store = Store.create!(name: "運営編集店舗", published: true)
    system_admin = User.create!(email: "store-show-system@example.com", password: "password", role: :system_admin)
    sign_in system_admin, scope: :user

    get store_path(store)

    assert_response :success
    assert_select "a.store-show-edit[href=?]", edit_admin_store_path(store, return_to: "store_detail"), count: 1

    store.update!(published: false)
    get store_path(store)
    assert_response :not_found

    admin = User.create!(email: "store-show-hidden-admin@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store:, user: admin, membership_role: :admin)
    sign_in admin, scope: :user
    get store_path(store)
    assert_response :not_found
  end
end
