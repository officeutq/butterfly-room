require "test_helper"

class CurrentSelectionUiTest < ActionDispatch::IntegrationTest
  %i[cast store_admin system_admin].each do |role|
    test "#{role}: 候補0件と1件では参照表示だけで複数の場合だけヘッダー切替を表示する" do
      actor = create_actor(role)
      get dashboard_path
      assert_header_links(booth: 0, store: 0)
      a = create_booth(actor, "A")
      get dashboard_path
      assert_header_links(booth: 0, store: 0)
      assert_select "#app_header [data-selection-booth-name]", text: "A"
      b = create_booth(actor, "B")
      get dashboard_path
      assert_header_links(booth: 1, store: role == :cast ? 0 : 1)
      assert_select "a[href='#{cast_booths_path}']", count: 0
      assert_select ".card-title", text: "ブース一覧", count: 0
      get select_modal_cast_booths_path(source: "header"), headers: { "Turbo-Frame" => "modal" }
      assert_select "form[action='#{cast_current_booth_path}'][data-turbo='false']", count: 2
      assert_select "a[href='#{edit_cast_booth_path(a)}']", count: 0
      post cast_current_booth_path, params: { booth_id: b.id, return_to: cast_booth_path(a) }, as: :json
      assert_response :success
      assert_equal cast_booth_path(b), response.parsed_body["redirect_url"]
      assert_equal b.id, @request.session[:current_booth_id]
      get cast_booth_path(b)
      assert_select "#app_header [data-selection-booth-name]", text: "B"
      assert_select "a[href='#{edit_cast_booth_path(b)}']"
      assert_select "a[href='#{cast_booth_stream_sessions_path(b)}']"
    end

    test "#{role}: 本人の配信中と離席中は店舗カードも切替リンクも出さず古いPOSTを拒否する" do
      actor = create_actor(role)
      a = create_booth(actor, "A")
      b = create_booth(actor, "B")
      stream = StreamSessions::StartService.new(booth: a, actor: actor).call
      stream.update!(actual_publisher_user: actor, actual_publisher_source: "ivs_verified",
        actual_publisher_recorded_at: Time.current, broadcast_started_at: Time.current)
      %i[live away].each do |status|
        a.update!(status: status)
        get dashboard_path
        assert_header_links(booth: 0, store: 0)
        assert_select ".card-title", text: "店舗を選択", count: 0
        post cast_current_booth_path, params: { booth_id: b.id }, as: :json
        assert_response :conflict
        assert_equal "配信を終了してから切り替えてください", response.parsed_body["message"]
        assert_equal a.id, @request.session[:current_booth_id]
      end
    end

    test "#{role}: 旧一覧は選択とモーダルを変えずダッシュボードへ戻す" do
      actor = create_actor(role)
      create_booth(actor, "A")
      create_booth(actor, "B")
      get cast_booths_path
      assert_redirected_to dashboard_path
      assert_nil @request.session[:current_booth_id]
      follow_redirect!
      assert_select "turbo-frame#modal[src]", count: 0
    end
  end

  %i[store_admin system_admin].each do |role|
    test "#{role}: 閉鎖済みだけの1件は固定し2件以上は同じモーダルで区別して選べる" do
      actor = create_actor(role)
      a = create_booth(actor, "A", archived: true)
      get dashboard_path
      assert_header_links(booth: 0, store: 0)
      b = create_booth(actor, "B", archived: true)
      get select_modal_cast_booths_path(source: "header"), headers: { "Turbo-Frame" => "modal" }
      assert_select ".badge", text: "閉鎖済み", count: 2
      post cast_current_booth_path, params: { booth_id: b.id, return_to: edit_cast_booth_path(a) }, as: :json
      assert_equal cast_booth_path(b), response.parsed_body["redirect_url"]
      b.update!(archived_at: nil)
      get select_modal_cast_booths_path(source: "header"), headers: { "Turbo-Frame" => "modal" }
      assert_select ".badge", text: "閉鎖済み", count: 1
    end
  end

  test "店舗選択のJSON応答は現在の画面の対象を置き換え招待の場合だけモーダルを維持する" do
    actor = create_actor(:store_admin)
    a = create_booth(actor, "A")
    b = create_booth(actor, "B")
    post admin_current_store_path, params: { store_id: b.store_id, return_to: edit_admin_store_path(a.store) }, as: :json
    assert_response :success
    assert_equal edit_admin_store_path(b.store), response.parsed_body["redirect_url"]
    post admin_current_store_path, params: { store_id: a.store_id, return_to_key: "cast_invitation" }, as: :json
    assert_equal "modal", response.parsed_body["frame"]
    assert_equal "店舗A", response.parsed_body["store_name"]
    assert_equal new_admin_cast_invitation_path, response.parsed_body["redirect_url"]
  end

  private

  def create_actor(role)
    User.create!(email: "ui-#{role}@example.com", password: "password", role: role).tap { |actor| sign_in actor }
  end

  def create_booth(actor, name, archived: false)
    store = Store.create!(name: "店舗#{name}", published: true)
    StoreMembership.create!(store: store, user: actor, membership_role: :admin) if actor.store_admin?
    Booth.create!(store: store, name: name, ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/#{name}",
      archived_at: archived ? Time.current : nil).tap do |booth|
      BoothCast.create!(booth: booth, cast_user: actor) if actor.cast?
    end
  end

  def assert_header_links(booth:, store:)
    assert_response :success
    assert_select "#app_header a[href^='#{select_modal_cast_booths_path}']", count: booth
    assert_select "#app_header a[href^='#{select_modal_admin_stores_path}']", count: store
  end
end
