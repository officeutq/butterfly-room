# frozen_string_literal: true

require "test_helper"

class HomeSearchTest < ActionDispatch::IntegrationTest
  def create_user!(email:, role:)
    User.create!(
      email: email,
      password: "password",
      password_confirmation: "password",
      role: role
    )
  end

  def create_store!(name:)
    Store.create!(name: name, published: true)
  end

  def create_booth!(store:, name:, status:, archived_at: nil, last_online_at: nil)
    Booth.create!(
      store: store,
      name: name,
      status: status,
      archived_at: archived_at,
      last_online_at: last_online_at
    )
  end

  # Booth.current_stream_session.started_at を並び替えで使うためのヘルパ
  def attach_current_stream_session!(booth:, started_at:, actor:)
    ss =
      StreamSession.create!(
        booth: booth,
        store: booth.store,
        started_by_cast_user: actor,
        status: :live,
        started_at: started_at
      )

    booth.update!(current_stream_session: ss)
    ss
  end

  def attach_image!(attachment)
    File.open(file_fixture("thumb.png"), "rb") do |io|
      attachment.attach(
        io: io,
        filename: "thumb.png",
        content_type: "image/png"
      )
    end
  end

  test "未ログイン: 3タブを表示し、店舗がデフォルトになる" do
    store = create_store!(name: "Guest Store")

    get root_path
    assert_response :success

    assert_select "a", text: "ブース", href: root_path(mode: "booths")
    assert_select "a.active", text: "店舗", href: root_path(mode: "stores")
    assert_select "a", text: "配信者", href: root_path(mode: "users")
    assert_select "input[name='mode'][value='stores']"
    assert_select "input[name='q'][placeholder='キーワード']"
    assert_includes @response.body, store.name

    assert_select "a[href=?][data-turbo-frame='modal']", guest_auth_prompt_path, text: /0pt/
    assert_select "a[href=?][data-turbo-frame='modal']", guest_auth_prompt_path, text: /GUEST.*未ログイン/m
    refute_includes @response.body, "guest@example.com"

    assert_select "#app_footer a[href=?]", root_path, text: /ホーム/
    assert_select "#app_footer a[href=?][data-turbo-frame='modal']", guest_auth_prompt_path, count: 3
    assert_select "#app_footer", text: /お気に入り.*お知らせ.*ダッシュボード/m
    refute_select "#app_footer", text: /配信/
  end

  test "未ログイン: ブース・配信者・お気に入りの導線は公式トップへ遷移する" do
    store = create_store!(name: "Guest Navigation Store")
    booth = create_booth!(store: store, name: "Guest Navigation Booth", status: :offline)
    cast = create_user!(email: "guest-navigation-cast@example.com", role: :cast)
    cast.update!(display_name: "Guest Navigation Cast")
    BoothCast.create!(booth: booth, cast_user: cast)

    get root_path, params: { mode: "booths" }
    assert_response :success

    assert_select "form[action=?][data-turbo-frame='modal']", guest_auth_prompt_path, minimum: 2
    assert_select "a[href=?][data-turbo-frame='modal']", guest_auth_prompt_path, text: cast.display_name
    assert_select "a.viewer-favorite-btn[href=?][data-turbo-frame='modal']", guest_auth_prompt_path, minimum: 3
    assert_select "a[href=?]", store_path(store), text: store.name

    get root_path, params: { mode: "users" }
    assert_response :success

    assert_select "a[href=?][data-turbo-frame='modal']", guest_auth_prompt_path, text: cast.display_name
    assert_select "a.viewer-favorite-btn[href=?][data-turbo-frame='modal']", guest_auth_prompt_path, minimum: 1
    assert_select "a.users-card-thumbnail-link[href=?][data-turbo-frame='modal']", guest_auth_prompt_path
  end

  test "qなし + mode未指定: booths がデフォルトで表示され、archived は出ない" do
    store1 = create_store!(name: "Alpha Store")
    store2 = create_store!(name: "Beta Store")

    booth_live = create_booth!(store: store1, name: "Rose Booth", status: :live)
    booth_off  = create_booth!(store: store2, name: "Tulip Booth", status: :offline)
    create_booth!(store: store1, name: "Archived Booth", status: :live, archived_at: Time.current)

    customer = create_user!(email: "customer@example.com", role: :customer)
    login_as(customer, scope: :user)

    get root_path
    assert_response :success

    # mode hidden が booths
    assert_includes @response.body, "value=\"booths\""
    # ドロップダウン表示がブース
    assert_includes @response.body, ">ブース<"

    # booths は出る
    assert_includes @response.body, booth_live.name
    assert_includes @response.body, booth_off.name

    # archived は出ない（Booth.active）
    refute_includes @response.body, "Archived Booth"
  end

  test "qあり + mode=booths: booth名の部分一致で絞り込まれる（store名一致では絞れない）" do
    store1 = create_store!(name: "Alpha Store")
    store2 = create_store!(name: "Beta Store")

    booth_hit  = create_booth!(store: store2, name: "Rose Booth", status: :live)
    booth_miss = create_booth!(store: store1, name: "Tulip Booth", status: :offline)

    customer = create_user!(email: "customer2@example.com", role: :customer)
    login_as(customer, scope: :user)

    # booth名検索
    get root_path, params: { mode: "booths", q: "Ros" }
    assert_response :success

    assert_includes @response.body, booth_hit.name
    refute_includes @response.body, booth_miss.name

    # store名で検索しても、boothsモードでは store名一致は検索対象外
    get root_path, params: { mode: "booths", q: "Alpha" }
    assert_response :success

    refute_includes @response.body, booth_hit.name
    refute_includes @response.body, booth_miss.name
  end

  test "qあり + mode=stores: store名の部分一致で絞り込まれる" do
    store1 = create_store!(name: "Alpha Store")
    store2 = create_store!(name: "Beta Store")

    create_booth!(store: store1, name: "Rose Booth", status: :live)
    create_booth!(store: store2, name: "Tulip Booth", status: :offline)

    customer = create_user!(email: "customer3@example.com", role: :customer)
    login_as(customer, scope: :user)

    get root_path, params: { mode: "stores", q: "Alpha" }
    assert_response :success

    # mode hidden が stores
    assert_includes @response.body, "value=\"stores\""
    # ドロップダウン表示が店舗
    assert_includes @response.body, ">店舗<"

    # store 絞り込み
    assert_includes @response.body, "Alpha Store"
    refute_includes @response.body, "Beta Store"

    # stores モードでは booth名は出ない（片方だけ表示）
    refute_includes @response.body, "Rose Booth"
    refute_includes @response.body, "Tulip Booth"
  end

  test "mode=stores: booth 0件の店舗も表示される" do
    store_with_booth = create_store!(name: "Has Booth Store")
    store_without_booth = create_store!(name: "No Booth Store")

    create_booth!(store: store_with_booth, name: "Live Booth", status: :live)

    customer = create_user!(email: "customer_empty_store@example.com", role: :customer)
    login_as(customer, scope: :user)

    get root_path, params: { mode: "stores" }
    assert_response :success

    assert_includes @response.body, "Has Booth Store"
    assert_includes @response.body, "No Booth Store"
  end

  test "mode=stores: archived boothしかない店舗は online 扱いされず、last_online_at がないため後ろに来る" do
    store_recent = create_store!(name: "Recent Offline Store")
    store_archived_only = create_store!(name: "Archived Only Store")

    create_booth!(
      store: store_recent,
      name: "Recent Offline Booth",
      status: :offline,
      last_online_at: Time.current - 1.day
    )

    create_booth!(
      store: store_archived_only,
      name: "Archived Booth",
      status: :live,
      archived_at: Time.current
    )

    customer = create_user!(email: "customer_archived_store@example.com", role: :customer)
    login_as(customer, scope: :user)

    get root_path, params: { mode: "stores" }
    assert_response :success

    body = @response.body

    assert_includes body, "Recent Offline Store"
    assert_includes body, "Archived Only Store"
    assert_operator body.index("Recent Offline Store"), :<, body.index("Archived Only Store")
  end

  test "archived は検索しても出ない（mode=booths）" do
    store = create_store!(name: "Alpha Store")
    create_booth!(store: store, name: "Archived Booth", status: :live, archived_at: Time.current)

    customer = create_user!(email: "customer4@example.com", role: :customer)
    login_as(customer, scope: :user)

    get root_path, params: { mode: "booths", q: "Archived" }
    assert_response :success

    refute_includes @response.body, "Archived Booth"
  end

  test "並び順: booths は online(live/away) が offline/standby より先、かつ online_started_at desc" do
    store = create_store!(name: "Alpha Store")

    customer = create_user!(email: "customer_order@example.com", role: :customer)
    actor    = create_user!(email: "cast_actor@example.com", role: :cast)
    login_as(customer, scope: :user)

    booth_live_new = create_booth!(store: store, name: "Live New", status: :live)
    booth_live_old = create_booth!(store: store, name: "Live Old", status: :live)
    booth_off      = create_booth!(store: store, name: "Offline Booth", status: :offline)
    booth_standby  = create_booth!(store: store, name: "Standby Booth", status: :standby)
    booth_away_mid = create_booth!(store: store, name: "Away Mid", status: :away)

    attach_current_stream_session!(booth: booth_live_new, started_at: Time.current - 10.minutes, actor: actor)
    attach_current_stream_session!(booth: booth_live_old, started_at: Time.current - 2.hours, actor: actor)
    attach_current_stream_session!(booth: booth_away_mid, started_at: Time.current - 1.hour, actor: actor)

    get root_path, params: { mode: "booths" }
    assert_response :success

    body = @response.body

    # online group 内で started_at desc：Live New(10m) → Away Mid(1h) → Live Old(2h)
    assert_operator body.index("Live New"), :<, body.index("Away Mid")
    assert_operator body.index("Away Mid"), :<, body.index("Live Old")

    # offline/standby は online より後ろ（ここでは代表で Offline Booth）
    assert_operator body.index("Live Old"), :<, body.index("Offline Booth")
    assert_operator body.index("Live Old"), :<, body.index("Standby Booth")
  end

  test "並び順: booths は started_at の次にサムネイルを優先し、last_online_at と id が続く" do
    store = create_store!(name: "Booth Thumbnail Order Store")
    reference_time = Time.current

    customer = create_user!(email: "booth_thumbnail_order_customer@example.com", role: :customer)
    actor = create_user!(email: "booth_thumbnail_order_cast@example.com", role: :cast)
    login_as(customer, scope: :user)

    online_new_without_thumbnail =
      create_booth!(store: store, name: "Online New Without Thumbnail", status: :live)
    online_old_with_thumbnail =
      create_booth!(store: store, name: "Online Old With Thumbnail", status: :live)

    attach_current_stream_session!(
      booth: online_new_without_thumbnail,
      started_at: reference_time - 5.minutes,
      actor: actor
    )
    attach_current_stream_session!(
      booth: online_old_with_thumbnail,
      started_at: reference_time - 1.hour,
      actor: actor
    )
    attach_image!(online_old_with_thumbnail.thumbnail_image)

    offline_thumbnail_old = create_booth!(
      store: store,
      name: "Offline Thumbnail Old",
      status: :offline,
      last_online_at: reference_time - 3.days
    )
    offline_thumbnail_new = create_booth!(
      store: store,
      name: "Offline Thumbnail New",
      status: :offline,
      last_online_at: reference_time - 2.days
    )
    attach_image!(offline_thumbnail_old.thumbnail_image)
    attach_image!(offline_thumbnail_new.thumbnail_image)

    offline_plain_recent = create_booth!(
      store: store,
      name: "Offline Plain Recent",
      status: :offline,
      last_online_at: reference_time - 1.hour
    )
    offline_plain_tie_old = create_booth!(
      store: store,
      name: "Offline Plain Tie Old Id",
      status: :offline,
      last_online_at: reference_time - 5.days
    )
    offline_plain_tie_new = create_booth!(
      store: store,
      name: "Offline Plain Tie New Id",
      status: :offline,
      last_online_at: reference_time - 5.days
    )

    get root_path, params: { mode: "booths" }
    assert_response :success

    body = @response.body

    assert_operator body.index(online_new_without_thumbnail.name), :<, body.index(online_old_with_thumbnail.name)
    assert_operator body.index(online_old_with_thumbnail.name), :<, body.index(offline_thumbnail_new.name)
    assert_operator body.index(offline_thumbnail_new.name), :<, body.index(offline_thumbnail_old.name)
    assert_operator body.index(offline_thumbnail_old.name), :<, body.index(offline_plain_recent.name)
    assert_operator body.index(offline_plain_recent.name), :<, body.index(offline_plain_tie_new.name)
    assert_operator body.index(offline_plain_tie_new.name), :<, body.index(offline_plain_tie_old.name)
  end

  test "並び順: stores は online優先 → online_started_at desc → offlineは last_online_at desc → id desc" do
    store_a = create_store!(name: "Alpha Store")
    store_b = create_store!(name: "Beta Store")
    store_c = create_store!(name: "Gamma Store")
    store_d = create_store!(name: "Delta Store")

    actor = create_user!(email: "cast_actor2@example.com", role: :cast)

    # onlineあり（started_at が新しい）
    booth_a_live = create_booth!(store: store_a, name: "A Live", status: :live)
    attach_current_stream_session!(booth: booth_a_live, started_at: Time.current - 5.minutes, actor: actor)

    # onlineあり（started_at が古い）
    booth_b_away = create_booth!(store: store_b, name: "B Away", status: :away)
    attach_current_stream_session!(booth: booth_b_away, started_at: Time.current - 3.hours, actor: actor)

    # onlineなし、last_online_at あり
    create_booth!(store: store_c, name: "C Offline", status: :offline, last_online_at: Time.current - 1.day)

    # booth 0件
    customer = create_user!(email: "customer_store_order@example.com", role: :customer)
    login_as(customer, scope: :user)

    get root_path, params: { mode: "stores" }
    assert_response :success

    body = @response.body

    # online優先。その中では started_at が新しい順
    assert_operator body.index("Alpha Store"), :<, body.index("Beta Store")

    # onlineなしグループは onlineありより後ろ
    assert_operator body.index("Beta Store"), :<, body.index("Gamma Store")

    # booth 0件の店舗は、last_online_at がある店舗より後ろ
    assert_operator body.index("Gamma Store"), :<, body.index("Delta Store")
  end

  test "並び順: stores は配信開始日時の次にサムネイルを優先し、last_online_at と id が続く" do
    reference_time = Time.current

    online_new_without_thumbnail = create_store!(name: "Online New Store Without Thumbnail")
    online_old_with_thumbnail = create_store!(name: "Online Old Store With Thumbnail")
    online_old_without_thumbnail = create_store!(name: "Online Old Store Without Thumbnail")
    offline_thumbnail_old = create_store!(name: "Offline Thumbnail Old Store")
    offline_thumbnail_new = create_store!(name: "Offline Thumbnail New Store")
    offline_plain_recent = create_store!(name: "Offline Plain Recent Store")
    offline_plain_tie_old = create_store!(name: "Offline Plain Tie Old Id Store")
    offline_plain_tie_new = create_store!(name: "Offline Plain Tie New Id Store")

    actor = create_user!(email: "store_thumbnail_order_cast@example.com", role: :cast)
    customer = create_user!(email: "store_thumbnail_order_customer@example.com", role: :customer)
    login_as(customer, scope: :user)

    online_new_booth =
      create_booth!(store: online_new_without_thumbnail, name: "Online New Store Booth", status: :live)
    online_old_thumbnail_booth =
      create_booth!(store: online_old_with_thumbnail, name: "Online Old Thumbnail Store Booth", status: :live)
    online_old_plain_booth =
      create_booth!(store: online_old_without_thumbnail, name: "Online Old Plain Store Booth", status: :live)

    attach_current_stream_session!(
      booth: online_new_booth,
      started_at: reference_time - 5.minutes,
      actor: actor
    )
    attach_current_stream_session!(
      booth: online_old_thumbnail_booth,
      started_at: reference_time - 1.hour,
      actor: actor
    )
    attach_current_stream_session!(
      booth: online_old_plain_booth,
      started_at: reference_time - 1.hour,
      actor: actor
    )
    attach_image!(online_old_with_thumbnail.thumbnail)

    create_booth!(
      store: offline_thumbnail_old,
      name: "Offline Thumbnail Old Store Booth",
      status: :offline,
      last_online_at: reference_time - 3.days
    )
    create_booth!(
      store: offline_thumbnail_new,
      name: "Offline Thumbnail New Store Booth",
      status: :offline,
      last_online_at: reference_time - 2.days
    )
    attach_image!(offline_thumbnail_old.thumbnail)
    attach_image!(offline_thumbnail_new.thumbnail)

    create_booth!(
      store: offline_plain_recent,
      name: "Offline Plain Recent Store Booth",
      status: :offline,
      last_online_at: reference_time - 1.hour
    )
    create_booth!(
      store: offline_plain_tie_old,
      name: "Offline Plain Tie Old Id Store Booth",
      status: :offline,
      last_online_at: reference_time - 5.days
    )
    create_booth!(
      store: offline_plain_tie_new,
      name: "Offline Plain Tie New Id Store Booth",
      status: :offline,
      last_online_at: reference_time - 5.days
    )

    get root_path, params: { mode: "stores" }
    assert_response :success

    body = @response.body

    assert_operator body.index(online_new_without_thumbnail.name), :<, body.index(online_old_with_thumbnail.name)
    assert_operator body.index(online_old_with_thumbnail.name), :<, body.index(online_old_without_thumbnail.name)
    assert_operator body.index(online_old_without_thumbnail.name), :<, body.index(offline_thumbnail_new.name)
    assert_operator body.index(offline_thumbnail_new.name), :<, body.index(offline_thumbnail_old.name)
    assert_operator body.index(offline_thumbnail_old.name), :<, body.index(offline_plain_recent.name)
    assert_operator body.index(offline_plain_recent.name), :<, body.index(offline_plain_tie_new.name)
    assert_operator body.index(offline_plain_tie_new.name), :<, body.index(offline_plain_tie_old.name)
  end

  test "customer のBAN: Homeで予防され、booths#show でも最終拒否される" do
    store = create_store!(name: "Alpha Store")
    booth = create_booth!(store: store, name: "Banned Booth", status: :live)

    customer = create_user!(email: "banned_customer@example.com", role: :customer)
    store_admin = create_user!(email: "store_admin@example.com", role: :store_admin)

    StoreBan.create!(
      store: store,
      customer_user: customer,
      created_by_store_admin_user: store_admin
    )

    login_as(customer, scope: :user)

    get root_path
    assert_response :success
    refute_includes @response.body, booth.name

    get booth_path(booth)
    assert_response :see_other
    assert_redirected_to root_path
  end

  test "mode切替: stores を選ぶと booths は表示されない（表示対象は片方のみ）" do
    store1 = create_store!(name: "Alpha Store")
    create_booth!(store: store1, name: "Rose Booth", status: :live)

    customer = create_user!(email: "customer_mode@example.com", role: :customer)
    login_as(customer, scope: :user)

    get root_path, params: { mode: "stores" }
    assert_response :success

    # stores モードになっている
    assert_includes @response.body, "value=\"stores\""
    assert_includes @response.body, ">店舗<"

    # booths は表示されない
    refute_includes @response.body, "Rose Booth"

    # store カードが出る
    assert_includes @response.body, "Alpha Store"
  end

  test "mode=users: 営業支援会社所属の store_admin を除外する" do
    regular_store = create_store!(name: "Regular User Search Store")
    sales_support_company = create_store!(name: "Sales Support Company")
    sales_support_company.update!(sales_support_company: true)

    cast_user = create_user!(email: "cast_search@example.com", role: :cast)
    cast_user.update!(display_name: "Cast Search User")
    StoreMembership.create!(store: sales_support_company, user: cast_user, membership_role: :cast)

    store_admin_user = create_user!(email: "store_admin_search@example.com", role: :store_admin)
    store_admin_user.update!(display_name: "Store Admin Search User")
    StoreMembership.create!(store: regular_store, user: store_admin_user, membership_role: :admin)

    support_company_cast_member =
      create_user!(email: "support_company_cast_member@example.com", role: :store_admin)
    support_company_cast_member.update!(display_name: "Support Company Cast Member")
    StoreMembership.create!(
      store: sales_support_company,
      user: support_company_cast_member,
      membership_role: :cast
    )

    support_company_admin = create_user!(email: "support_company_admin@example.com", role: :store_admin)
    support_company_admin.update!(display_name: "Sales Support Company Admin")
    StoreMembership.create!(
      store: sales_support_company,
      user: support_company_admin,
      membership_role: :admin
    )

    dual_store_admin = create_user!(email: "dual_store_admin@example.com", role: :store_admin)
    dual_store_admin.update!(display_name: "Dual Store Admin")
    StoreMembership.create!(store: regular_store, user: dual_store_admin, membership_role: :admin)
    StoreMembership.create!(store: sales_support_company, user: dual_store_admin, membership_role: :admin)

    hidden_customer_user = create_user!(email: "hidden_customer_search@example.com", role: :customer)
    hidden_customer_user.update!(display_name: "Hidden Customer Search User")

    system_admin_user = create_user!(email: "system_admin_search@example.com", role: :system_admin)
    system_admin_user.update!(display_name: "System Admin Search User")

    deleted_cast_user = create_user!(email: "deleted_cast_search@example.com", role: :cast)
    deleted_cast_user.update!(display_name: "Deleted Cast Search User", deleted_at: Time.current)

    get root_path, params: { mode: "users" }
    assert_response :success

    guest_body = @response.body

    assert_includes guest_body, "Cast Search User"
    assert_includes guest_body, "Store Admin Search User"
    assert_includes guest_body, "Support Company Cast Member"
    refute_includes guest_body, "Sales Support Company Admin"
    refute_includes guest_body, "Dual Store Admin"

    login_user = create_user!(email: "login_customer_search@example.com", role: :customer)
    login_user.update!(display_name: "Login Customer Search User")
    login_as(login_user, scope: :user)

    get root_path, params: { mode: "users" }
    assert_response :success

    body = @response.body

    assert_includes body, "value=\"users\""
    assert_includes body, ">配信者<"
    refute_includes body, ">ユーザー<"

    assert_includes body, "Cast Search User"
    assert_includes body, "Store Admin Search User"
    assert_includes body, "Support Company Cast Member"

    refute_includes body, "Sales Support Company Admin"
    refute_includes body, "Dual Store Admin"
    refute_includes body, "Hidden Customer Search User"
    refute_includes body, "System Admin Search User"
    refute_includes body, "Deleted Cast Search User"
  end

  test "並び順: users は display_name → avatar → bio → id の優先順で表示される" do
    customer = create_user!(email: "user_profile_order_customer@example.com", role: :customer)

    plain_old = create_user!(email: "user_profile_order_plain_old@example.com", role: :cast)
    plain_old.update!(display_name: "Profile Plain Old Id")

    plain_new = create_user!(email: "user_profile_order_plain_new@example.com", role: :cast)
    plain_new.update!(display_name: "Profile Plain New Id")

    bio_without_avatar = create_user!(email: "user_profile_order_bio@example.com", role: :cast)
    bio_without_avatar.update!(display_name: "Profile Bio Without Avatar", bio: "Bio Without Avatar Marker")

    avatar_without_bio = create_user!(email: "user_profile_order_avatar@example.com", role: :cast)
    avatar_without_bio.update!(display_name: "Profile Avatar Without Bio")
    attach_image!(avatar_without_bio.avatar)

    avatar_with_bio = create_user!(email: "user_profile_order_full@example.com", role: :cast)
    avatar_with_bio.update!(display_name: "Profile Avatar With Bio", bio: "Avatar With Bio Marker")
    attach_image!(avatar_with_bio.avatar)

    unnamed_full = create_user!(email: "user_profile_order_unnamed@example.com", role: :cast)
    unnamed_full.update!(bio: "Unnamed Full Profile Marker")
    attach_image!(unnamed_full.avatar)

    deleted_full = create_user!(email: "user_profile_order_deleted@example.com", role: :cast)
    deleted_full.update!(
      display_name: "Deleted Full Profile",
      bio: "Deleted Full Profile Marker",
      deleted_at: Time.current
    )
    attach_image!(deleted_full.avatar)

    login_as(customer, scope: :user)

    get root_path, params: { mode: "users" }
    assert_response :success

    body = @response.body

    assert_operator body.index(avatar_with_bio.display_name), :<, body.index(avatar_without_bio.display_name)
    assert_operator body.index(avatar_without_bio.display_name), :<, body.index(bio_without_avatar.display_name)
    assert_operator body.index(bio_without_avatar.display_name), :<, body.index(plain_new.display_name)
    assert_operator body.index(plain_new.display_name), :<, body.index(plain_old.display_name)
    assert_operator body.index(plain_old.display_name), :<, body.index(unnamed_full.bio)
    refute_includes body, deleted_full.display_name
  end

  test "qあり + mode=users: display_name の部分一致で絞り込まれる" do
    cast_hit = create_user!(email: "users_hit@example.com", role: :cast)
    cast_hit.update!(display_name: "Rose User")

    cast_miss = create_user!(email: "users_miss@example.com", role: :cast)
    cast_miss.update!(display_name: "Tulip User")

    sales_support_company = create_store!(name: "Users Search Support Company")
    sales_support_company.update!(sales_support_company: true)
    hidden_support_admin = create_user!(email: "users_hidden_support_admin@example.com", role: :store_admin)
    hidden_support_admin.update!(display_name: "Rose Support Admin")
    StoreMembership.create!(
      store: sales_support_company,
      user: hidden_support_admin,
      membership_role: :admin
    )

    customer = create_user!(email: "users_search_customer@example.com", role: :customer)
    login_as(customer, scope: :user)

    get root_path, params: { mode: "users", q: "Ros" }
    assert_response :success

    body = @response.body

    assert_includes body, "Rose User"
    refute_includes body, "Tulip User"
    refute_includes body, "Rose Support Admin"
  end

  test "mode=users: ユーザー名クリックで user詳細に遷移できるリンクが含まれる" do
    user = create_user!(email: "users_link@example.com", role: :cast)
    user.update!(display_name: "Link User")

    customer = create_user!(email: "users_link_customer@example.com", role: :customer)
    login_as(customer, scope: :user)

    get root_path, params: { mode: "users" }
    assert_response :success

    assert_includes @response.body, user_path(user)
  end
end
