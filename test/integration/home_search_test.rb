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
    Store.create!(name: name)
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

  test "未ログイン: ようこそ表示が出て、検索欄は出ない" do
    get root_path
    assert_response :success

    assert_includes @response.body, "ようこそ"
    refute_includes @response.body, "input-group"
    refute_includes @response.body, "mode"
    refute_includes @response.body, "placeholder=\"ブース名 / ストア名で検索（部分一致）\""
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
end
