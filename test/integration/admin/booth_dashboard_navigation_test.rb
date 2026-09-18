require "test_helper"

class Admin::BoothDashboardNavigationTest < ActionDispatch::IntegrationTest
  setup do
    client = Object.new
    client.define_singleton_method(:create_stage!) { |**| "arn:aws:ivs:ap-northeast-1:123456789012:stage/test" }
    Ivs::Client.factory = ->(region:) { client }
  end

  teardown do
    Ivs::Client.reset_factory!
  end

  %i[store_admin system_admin].each do |role|
    test "#{role}: 作成カードは店舗・ブースなしでも表示し店舗があれば作成できる" do
      actor = sign_in_role(role)
      get dashboard_path
      assert_cards
      get new_admin_booth_path
      assert_response :conflict
      assert_includes response.body, "管理可能な店舗がありません"
      store = add_store(actor, "初店舗")
      get new_admin_booth_path
      assert_form(store)
      assert_nil @request.session[:current_booth_id]
      assert_no_difference "StreamSession.count" do
        assert_difference "Booth.count", 1 do
          post admin_booths_path, params: { selection_store_id: store.id, booth: { name: "最初のブース" } }
        end
      end
      assert_redirected_to dashboard_path
      follow_redirect!
      assert_cards
      assert_equal store.booths.sole.id, @request.session[:current_booth_id]
    end

    test "#{role}: 複数店舗の未選択は共通選択から作成へ戻り唯一の別店舗ブースを補完しない" do
      actor = sign_in_role(role)
      a = add_store(actor, "店舗A")
      b = add_store(actor, "店舗B")
      get new_admin_booth_path
      assert_redirected_to select_modal_admin_stores_path(return_to: new_admin_booth_path, required: 1)
      follow_redirect!(headers: { "Turbo-Frame" => "modal" })
      assert_response :success
      post admin_current_store_path, params: { store_id: b.id, return_to: new_admin_booth_path }, as: :json
      assert_equal new_admin_booth_path, response.parsed_body["redirect_url"]
      Booth.create!(store: a, name: "Aの唯一のブース")
      get response.parsed_body["redirect_url"]
      assert_form(b)
      assert_nil @request.session[:current_booth_id]
      assert_difference "b.booths.count", 1 do
        post admin_booths_path, params: { selection_store_id: b.id, booth: { name: "Bの新ブース" } }, as: :json
      end
      assert_equal dashboard_path, response.parsed_body["redirect_url"]
      get dashboard_path
      assert_cards
      assert_equal b.id, @request.session[:current_store_id]
      assert_nil @request.session[:current_booth_id]
    end

    test "#{role}: 閉鎖済み選択・全件閉鎖でも作成でき既存の選択を上書きしない" do
      actor = sign_in_role(role)
      store = add_store(actor, "閉鎖店舗")
      closed = Booth.create!(store: store, name: "閉鎖ブース", archived_at: Time.current)
      get dashboard_path
      assert_cards
      assert_select "a[href=?]", cast_booth_path(closed)
      get new_admin_booth_path
      assert_form(store)
      post admin_booths_path, params: { selection_store_id: store.id, booth: { name: "再開ブース" } }
      assert_redirected_to dashboard_path
      follow_redirect!
      assert_equal closed.id, @request.session[:current_booth_id]
      get cast_booth_path(closed)
      assert_response :success
      assert_select ".booth-show-actions a", count: 1
      assert_select ".booth-show-actions a[href=?]", cast_booth_stream_sessions_path(closed)
      assert_select "a[href=?]", new_admin_booth_path, count: 0
    end

    test "#{role}: 本人配信中・離席中の新規作成でも配信と選択を維持する" do
      actor = sign_in_role(role)
      store = add_store(actor, "配信店舗")
      add_store(actor, "別店舗")
      booth = Booth.create!(store: store, name: "配信ブース")
      Booth.create!(store: store, name: "別ブース")
      stream = StreamSession.create!(booth: booth, store: store, started_by_cast_user: actor,
        status: :live, started_at: 1.minute.ago, broadcast_started_at: 1.minute.ago,
        actual_publisher_user: actor, actual_publisher_source: "ivs_verified", actual_publisher_recorded_at: 1.minute.ago)
      %i[live away].each do |state|
        booth.update!(status: state, current_stream_session: stream)
        before = [ booth.reload.attributes, stream.reload.attributes ]
        get dashboard_path
        assert_cards
        assert_select "#app_header [data-selection-lock-target='link']", count: 0
        get new_admin_booth_path
        assert_form(store)
        post admin_booths_path, params: { selection_store_id: store.id, booth: { name: "作成#{state}" } }
        assert_redirected_to dashboard_path
        follow_redirect!
        assert_equal booth.id, @request.session[:current_booth_id]
        assert_equal store.id, @request.session[:current_store_id]
        assert_equal before, [ booth.reload.attributes, stream.reload.attributes ]
      end
    end

    test "#{role}: 店舗切替後の古い作成フォームは別店舗へ保存しない" do
      actor = sign_in_role(role)
      a = add_store(actor, "旧店舗")
      b = add_store(actor, "新店舗")
      post admin_current_store_path, params: { store_id: a.id }, as: :json
      get new_admin_booth_path
      assert_form(a)
      post admin_current_store_path, params: { store_id: b.id, return_to: new_admin_booth_path }, as: :json
      assert_equal new_admin_booth_path, response.parsed_body["redirect_url"]
      assert_no_difference "Booth.count" do
        post admin_booths_path, params: { selection_store_id: a.id, booth: { name: "古い入力" } }, as: :json
      end
      assert_response :conflict
      assert_equal b.id, @request.session[:current_store_id]
      get new_admin_booth_path
      assert_form(b)
    end
  end

  test "キャスト・視聴者は作成カードを持たず直接要求でも作成できない" do
    %i[cast customer].each do |role|
      actor = sign_in_role(role)
      get dashboard_path
      assert_select ".card-title", text: "ブース新規作成", count: 0
      get new_admin_booth_path
      assert_response :forbidden
      assert_no_difference "Booth.count" do
        post admin_booths_path, params: { booth: { name: "許可されない作成" } }
      end
      assert_response :forbidden
      sign_out actor
    end
  end

  private

  def sign_in_role(role)
    User.create!(email: "dashboard-create-#{role}@example.com", password: "password", role: role).tap { |actor| sign_in actor }
  end

  def add_store(actor, name)
    Store.create!(name: name).tap { |store| StoreMembership.create!(store: store, user: actor, membership_role: :admin) }
  end

  def assert_cards
    assert_response :success
    assert_select ".card-title", text: "ブース情報", count: 1
    path = @request.session[:current_store_id] ? new_admin_booth_path : select_modal_admin_stores_path(return_to: new_admin_booth_path, required: 1)
    assert_select "a[href=?] .dashboard-role-card-store-admin .card-title", path, text: "ブース新規作成", count: 1
    assert_select ".card-title", text: /\Aブース(管理|一覧)\z/, count: 0
    assert_select "a[href=?]", admin_booths_path, count: 0
  end

  def assert_form(store)
    assert_response :success
    assert_select "form[action=?]", admin_booths_path
    assert_select ".booth-form__readonly-value", text: store.name
    assert_select "input[name='selection_store_id'][value=?]", store.id
    assert_select "a.booth-form__back[href=?]", dashboard_path
  end
end
