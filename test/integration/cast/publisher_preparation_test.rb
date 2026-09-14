require "test_helper"

class Cast::PublisherPreparationTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "Preparation entry", published: true)
    @creator = User.create!(email: "entry_creator@example.com", password: "password", role: :cast)
    @publisher = User.create!(email: "entry_publisher@example.com", password: "password", role: :store_admin)
    StoreMembership.create!(store: @store, user: @publisher, membership_role: :admin)
    @booth = Booth.create!(store: @store, name: "Target booth", status: :standby,
      ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/entry")
    @selected_booth = Booth.create!(store: @store, name: "Previously selected", status: :offline, ivs_stage_arn: "selected-stage")
    BoothCast.create!(booth: @booth, cast_user: @creator)
    @session = StreamSession.create!(store: @store, booth: @booth, started_by_cast_user: @creator,
      started_at: 10.minutes.ago, status: :live, title: "旧準備タイトル", ivs_stage_arn: @booth.ivs_stage_arn)
    @booth.update!(current_stream_session: @session)
    @client = Aws::IVSRealTime::Client.new(stub_responses: true)
    @client.stub_responses(:get_stage, { stage: { arn: @booth.ivs_stage_arn } })
    sign_in @publisher, scope: :user
  end

  test "P02 M01 店舗管理者が旧準備へ入っても同じID X タイトルで画面を表示する" do
    new_control do
      before = @session.attributes
      post enter_as_cast_booth_path(@booth)
      assert_redirected_to live_cast_booth_path(@booth)
      follow_redirect!
      assert_response :success
      assert_select ".cast-live-screen[data-ivs-publisher-auto-resume-on-entry-value='false']"
      assert_equal before, @session.reload.attributes
      assert_equal @booth.id, @request.session[:current_booth_id]
    end
  end

  test "P04 XがYの配信画面を直接開いても拒否しYだけが復帰できる" do
    @session.update!(actual_publisher_user: @publisher, actual_publisher_source: "ivs_verified",
      actual_publisher_recorded_at: Time.current, broadcast_started_at: 5.minutes.ago)
    @booth.update!(status: :away)
    new_control do
      get live_cast_booth_path(@booth)
      assert_response :success
      assert_select ".cast-live-screen[data-ivs-publisher-auto-resume-on-entry-value='true']"
      sign_out :user
      sign_in @creator, scope: :user
      get live_cast_booth_path(@booth)
      assert_response :conflict
      assert_select ".cast-live-screen", count: 0
      assert_includes response.body, "このブースはすでに他の人が配信中です"
      assert_empty @client.api_requests
      assert_equal @publisher, @session.reload.actual_publisher_user
    end
  end

  test "S06 公開入口 選択入口 配信画面直リンクの照会失敗で元の選択を維持する" do
    new_control do
      select_previous_booth
      @client.stub_responses(:get_stage, "AccessDeniedException")
      [ -> { post enter_as_cast_booth_path(@booth) },
        -> { post cast_current_booth_path, params: { booth_id: @booth.id, return_to_key: "booth_live" } },
        -> { get live_cast_booth_path(@booth) } ].each do |request_action|
        request_action.call
        assert_response :service_unavailable
        assert_equal @selected_booth.id, @request.session[:current_booth_id]
        assert_equal @session.id, @booth.reload.current_stream_session_id
        assert_select "form[action='#{enter_as_cast_booth_path(@booth)}'] button", text: "再確認"
        assert_select ".cast-live-screen", count: 0
      end
      @client.stub_responses(:get_stage, { stage: { arn: @booth.ivs_stage_arn } })
      post enter_as_cast_booth_path(@booth)
      assert_redirected_to live_cast_booth_path(@booth)
      assert_equal @booth.id, @request.session[:current_booth_id]
      assert_equal @creator.id, @session.reload.started_by_cast_user_id
    end
  end

  test "S06 キャスト本人の公開入口でも失敗時に元の選択を維持する" do
    BoothCast.create!(booth: @selected_booth, cast_user: @creator)
    sign_out :user
    sign_in @creator, scope: :user
    new_control do
      select_previous_booth
      @client.stub_responses(:get_stage, "AccessDeniedException")
      get enter_booth_path(@booth)
      assert_response :service_unavailable
      assert_equal @selected_booth.id, @request.session[:current_booth_id]
      assert_equal @session.id, @booth.reload.current_stream_session_id
    end
  end

  test "S06 モーダル入口は同じフレーム内に再確認を表示する" do
    @selected_booth.update!(archived_at: Time.current)
    new_control do
      @client.stub_responses(:get_stage, "AccessDeniedException")
      get select_modal_cast_booths_path, headers: { "Turbo-Frame" => "modal" }
      assert_response :service_unavailable
      assert_select "turbo-frame#modal form[action='#{enter_as_cast_booth_path(@booth)}']"
    end
  end

  test "S06 配信準備POSTとJSON要求にも同じ確認不能を返す" do
    new_control do
      select_previous_booth
      @client.stub_responses(:get_stage, "AccessDeniedException")
      post cast_booth_stream_sessions_path(@booth)
      assert_response :service_unavailable
      assert_select "form[action='#{enter_as_cast_booth_path(@booth)}']"
      assert_equal @selected_booth.id, @request.session[:current_booth_id]
      assert_nil @selected_booth.reload.current_stream_session_id
      post enter_as_cast_booth_path(@booth), as: :json
      assert_response :service_unavailable
      assert_equal "publisher_state_unavailable", response.parsed_body["error"]
    end
  end

  test "準備POSTは現在選択中のAではなくURLで指定したBへ入る" do
    new_control do
      select_previous_booth
      assert_no_difference "StreamSession.count" do
        post cast_booth_stream_sessions_path(@booth)
      end
      assert_redirected_to live_cast_booth_path(@booth)
      assert_equal @booth.id, @request.session[:current_booth_id]
      assert_equal @session.id, @booth.reload.current_stream_session_id
      assert_nil @selected_booth.reload.current_stream_session_id
    end
  end

  test "P01 情報の閲覧と情報用選択では外部確認も準備作成もしない" do
    new_control do
      assert_no_difference "StreamSession.count" do
        get cast_booth_path(@selected_booth)
        assert_response :success
        select_previous_booth
        get booth_path(@booth)
        assert_response :success
      end
      assert_empty @client.api_requests
      assert_nil @selected_booth.reload.current_stream_session_id
    end
  end

  test "P05 権限外の直接要求でも元の有効な選択を消さない" do
    other_store = Store.create!(name: "Not managed")
    forbidden_booth = Booth.create!(store: other_store, name: "Forbidden")
    new_control do
      select_previous_booth
      get live_cast_booth_path(forbidden_booth)
      assert_response :forbidden
      assert_equal @selected_booth.id, @request.session[:current_booth_id]
      post cast_current_booth_path, params: { booth_id: forbidden_booth.id, return_to_key: "booth_live" }
      assert_response :redirect
      assert_equal @selected_booth.id, @request.session[:current_booth_id]
      assert_empty @client.api_requests
    end
  end

  private

  def new_control
    original_constructor = Aws::IVSRealTime::Client.method(:new)
    client = @client
    Aws::IVSRealTime::Client.define_singleton_method(:new) { |**_options| client }
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      yield
    end
  ensure
    Aws::IVSRealTime::Client.define_singleton_method(:new, original_constructor)
  end

  def select_previous_booth
    post cast_current_booth_path, params: { booth_id: @selected_booth.id, return_to_key: "booth_show" }
    assert_response :redirect
    assert_equal @selected_booth.id, @request.session[:current_booth_id]
  end
end
