require "test_helper"

class CurrentSelectionEntryTest < ActionDispatch::IntegrationTest
  setup do
    @actor = User.create!(email: "selection-entry@example.com", password: "password", role: :store_admin)
    @a = Store.create!(name: "選択店舗A")
    @b = Store.create!(name: "選択店舗B")
    [ @a, @b ].each { |store| StoreMembership.create!(store: store, user: @actor, membership_role: :admin) }
    @booth_a = Booth.create!(store: @a, name: "選択ブースA")
    sign_in @actor
  end

  test "唯一ブースが別店舗なら通常表示では補完せず必要操作でだけ自動設定する" do
    get dashboard_path
    assert_selection(@a, @booth_a)
    post admin_current_store_path, params: { store_id: @b.id }
    assert_selection(@b, nil)
    2.times do
      get dashboard_path
      assert_response :success
      assert_selection(@b, nil)
    end
    get cast_booth_path(@booth_a)
    assert_response :success
    assert_selection(@a, @booth_a)
    post admin_current_store_path, params: { store_id: @b.id }
    post admin_current_store_path, params: { store_id: @a.id }
    assert_selection(@a, @booth_a)
    post admin_current_store_path, params: { store_id: @a.id }
    assert_selection(@a, @booth_a)
  end

  test "選択済みの別ブースURLは情報と編集と履歴を表示せず保存も拒否する" do
    add_booth_b
    select_booth(@booth_a)
    [ cast_booth_path(@booth_b), edit_cast_booth_path(@booth_b), cast_booth_stream_sessions_path(@booth_b) ].each do |path|
      get path
      assert_response :conflict
      assert_includes response.body, "対象のブースをヘッダーから選択してください"
      assert_select "form[action='#{cast_booth_path(@booth_b)}']", count: 0
      assert_selection(@a, @booth_a)
    end
    patch cast_booth_path(@booth_b), params: { booth: { name: "誤更新" } }, as: :json
    assert_response :conflict
    assert_equal "選択ブースB", @booth_b.reload.name
    assert_selection(@a, @booth_a)
  end

  test "不正な要求や別店舗の旧フォームでも有効な選択を消さない" do
    add_booth_b
    select_booth(@booth_a)
    post cast_current_booth_path, params: { booth_id: -1 }
    assert_response :conflict
    assert_selection(@a, @booth_a)
    post admin_current_store_path, params: { store_id: -1 }
    assert_response :conflict
    assert_selection(@a, @booth_a)
    patch admin_store_path(@b), params: { store: { name: "誤更新" } }, as: :json
    assert_response :conflict
    assert_equal "選択店舗B", @b.reload.name
    assert_selection(@a, @booth_a)
  end

  test "ヘッダーの戻り先は新しい対象の同種画面へ組み立てる" do
    add_booth_b
    select_booth(@booth_a)
    post cast_current_booth_path, params: { booth_id: @booth_b.id, return_to: edit_cast_booth_path(@booth_a) }
    assert_redirected_to edit_cast_booth_path(@booth_b)
    assert_selection(@b, @booth_b)
    post admin_current_store_path, params: { store_id: @a.id, return_to: edit_admin_store_path(@b) }
    assert_redirected_to edit_admin_store_path(@a)
    assert_selection(@a, nil)
  end

  test "管理者の閉鎖済み選択は情報と履歴で保持しキャストには許可しない" do
    add_booth_b
    @booth_b.update!(archived_at: Time.current)
    select_booth(@booth_b)
    get cast_booth_path(@booth_b)
    assert_response :success
    get cast_booth_stream_sessions_path(@booth_b)
    assert_response :success
    assert_selection(@b, @booth_b)
    @actor.update!(role: :cast)
    BoothCast.create!(booth: @booth_a, cast_user: @actor)
    BoothCast.create!(booth: @booth_b, cast_user: @actor)
    post cast_current_booth_path, params: { booth_id: @booth_b.id }
    assert_response :conflict
    assert_selection(@a, @booth_a)
    get cast_booth_stream_sessions_path(@booth_b)
    assert_response :success
    assert_selection(@a, @booth_a)
  end

  test "本人の配信開始後の次のアクセスで固定し古い選択POSTを拒否する" do
    add_booth_b
    select_booth(@booth_b)
    stream = StreamSession.create!(booth: @booth_a, store: @a, started_by_cast_user: @actor,
      status: :live, started_at: 10.minutes.ago, broadcast_started_at: 5.minutes.ago,
      actual_publisher_user: @actor, actual_publisher_source: "ivs_verified", actual_publisher_recorded_at: Time.current)
    @booth_a.update!(status: :away, current_stream_session: stream)
    post cast_current_booth_path, params: { booth_id: @booth_b.id }
    assert_response :conflict
    assert_selection(@a, @booth_a)
    post admin_current_store_path, params: { store_id: @b.id }
    assert_response :conflict
    assert_selection(@a, @booth_a)
    assert_equal :recorded, stream.reload.publisher_recording_state
  end

  test "モーダル表示と選択だけでは準備を作らず他者配信を優先しない" do
    add_booth_b
    @booth_b.update!(status: :live)
    assert_no_difference "StreamSession.count" do
      get select_modal_cast_booths_path(return_to_key: "booth_show"), headers: { "Turbo-Frame" => "modal" }
      assert_response :success
      assert_select "form input[name='booth_id']", count: 2
      assert_nil @request.session[:current_booth_id]
      select_booth(@booth_a)
      get select_modal_cast_booths_path(source: "header", return_to: cast_booth_path(@booth_a)), headers: { "Turbo-Frame" => "modal" }
      assert_select "form input[name='booth_id']", count: 2
      assert_selection(@a, @booth_a)
    end
  end

  test "ドリンク新規と口座の古いフォームは別店舗へ保存しない" do
    get dashboard_path
    post admin_current_store_path, params: { store_id: @b.id }
    assert_no_difference [ "DrinkItem.count", "StorePayoutAccount.count" ] do
      post admin_drink_items_path, params: { selection_store_id: @a.id, drink_item: { name: "誤作成", price_points: 500 } }, as: :turbo_stream
      assert_response :conflict
      assert_select "turbo-stream[target='flash_inner']"
      patch admin_payout_account_path, params: { selection_store_id: @a.id, store_payout_account: {} }, as: :turbo_stream
      assert_response :conflict
    end
    assert_selection(@b, nil)
  end

  test "古いHTML編集フォームも入力を保持して409を返す" do
    add_booth_b
    select_booth(@booth_a)
    patch cast_booth_path(@booth_b), params: { booth: { name: "保存前のB入力" } }
    assert_response :conflict
    assert_select "form[action='#{cast_booth_path(@booth_b)}'] input[name='booth[name]'][value='保存前のB入力']"
    assert_equal "選択ブースB", @booth_b.reload.name
    patch admin_store_path(@b), params: { store: { name: "保存前の店舗B入力" } }
    assert_response :conflict
    assert_select "form[action='#{admin_store_path(@b)}'] input[name='store[name]'][value='保存前の店舗B入力']"
    assert_equal "選択店舗B", @b.reload.name
    assert_selection(@a, @booth_a)
  end

  test "配信や選択入口の先読みは準備も選択変更も起こさない" do
    add_booth_b
    select_booth(@booth_a)
    assert_no_difference "StreamSession.count" do
      [ enter_booth_path(@booth_b), live_cast_booth_path(@booth_b), select_modal_cast_booths_path ].each do |path|
        get path, headers: { "X-Sec-Purpose" => "prefetch" }
        assert_response :no_content
        assert_selection(@a, @booth_a)
      end
    end
  end

  test "公開詳細や特定リザルトは表示対象を保持しヘッダーだけ選択に従う" do
    add_booth_b
    @b.update!(published: true)
    history = StreamSession.create!(booth: @booth_b, store: @b, started_by_cast_user: @actor,
      status: :ended, started_at: 1.hour.ago, ended_at: Time.current, title: "Bの履歴")
    select_booth(@booth_a)
    [ store_path(@b), booth_path(@booth_b), cast_stream_session_path(history) ].each do |path|
      get path
      assert_response :success
      assert_selection(@a, @booth_a)
    end
    post cast_current_booth_path, params: { booth_id: @booth_b.id, return_to: cast_stream_session_path(history) }
    assert_redirected_to cast_stream_session_path(history)
  end

  private

  def add_booth_b
    @booth_b = Booth.create!(store: @b, name: "選択ブースB")
  end

  def select_booth(booth)
    post cast_current_booth_path, params: { booth_id: booth.id, return_to_key: "booth_show" }
    assert_redirected_to cast_booth_path(booth)
  end

  def assert_selection(store, booth)
    assert_equal store.id, @request.session[:current_store_id]
    if booth
      assert_equal booth.id, @request.session[:current_booth_id]
    else
      assert_nil @request.session[:current_booth_id]
    end
  end
end
