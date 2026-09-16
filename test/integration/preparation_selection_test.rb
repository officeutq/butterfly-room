require "test_helper"

class PreparationSelectionTest < ActionDispatch::IntegrationTest
  setup do
    @actor = User.create!(email: "preparation-selection@example.com", password: "password", role: :store_admin)
    @other = User.create!(email: "preparation-other@example.com", password: "password", role: :cast)
    @a, @b = %w[A B].map do |name|
      store = Store.create!(name: "準備店舗#{name}")
      StoreMembership.create!(store: store, user: @actor, membership_role: :admin)
      Booth.create!(store: store, name: "準備#{name}", ivs_stage_arn: "arn:aws:ivs:ap-northeast-1:123456789012:stage/#{name}")
    end
    @preparation_a = prepare(@a, @actor)
    @client = Aws::IVSRealTime::Client.new(stub_responses: true)
    @client.stub_responses(:get_stage, { stage: { arn: @b.ivs_stage_arn } })
    sign_in @actor
    post cast_current_booth_path, params: { booth_id: @a.id, return_to_key: "booth_show" }
  end

  test "空きBを準備してから選択しAの準備とタイトルを保持する" do
    new_control do
      before = @preparation_a.attributes
      assert_difference "StreamSession.count", 1 do
        switch_to_b
        assert_response :success
      end
      assert_equal live_cast_booth_path(@b), response.parsed_body["redirect_url"]
      assert_equal @b.id, @request.session[:current_booth_id]
      assert_equal @b.store_id, @request.session[:current_store_id]
      assert_nil @b.reload.current_stream_session.broadcast_started_at
      assert_equal before, @preparation_a.reload.attributes
      assert_equal "standby", @a.reload.status
    end
  end

  test "他者が作った未配信準備は同じIDとタイトルのまま再利用する" do
    preparation = prepare(@b, @other)
    new_control do
      before = preparation.attributes
      assert_no_difference "StreamSession.count" do
        switch_to_b
        assert_response :success
      end
      assert_equal before, preparation.reload.attributes
      assert_equal live_cast_booth_path(@b), response.parsed_body["redirect_url"]
    end
  end

  %i[live away].each do |status|
    test "他者#{status}のBは準備せず選択して情報で案内する" do
      stream = prepare(@b, @other)
      record_publisher(stream, @other, status)
      new_control do
        before = stream.attributes
        assert_no_difference "StreamSession.count" do
          switch_to_b
          assert_response :success
          assert_equal cast_booth_path(@b), response.parsed_body["redirect_url"]
          assert_equal @b.id, @request.session[:current_booth_id]
          get live_cast_booth_path(@b)
          assert_redirected_to cast_booth_path(@b)
          follow_redirect!
          assert_includes response.body, "このブースはすでに他の人が配信中です"
        end
        assert_equal before, stream.reload.attributes
        assert_empty @client.api_requests
      end
    end
  end

  test "閉鎖済みBは選択して情報に移り直接準備URLとPOSTでも開始しない" do
    @b.update!(archived_at: Time.current)
    new_control do
      assert_no_difference "StreamSession.count" do
        switch_to_b
        assert_response :success
        assert_equal cast_booth_path(@b), response.parsed_body["redirect_url"]
        get live_cast_booth_path(@b)
        assert_redirected_to cast_booth_path(@b)
        post cast_booth_stream_sessions_path(@b)
        assert_redirected_to cast_booth_path(@b)
        follow_redirect!
        assert_includes response.body, Booths::PrepareSelectedBoothService::CLOSED_MESSAGE
      end
      assert_equal @b.id, @request.session[:current_booth_id]
      assert_empty @client.api_requests
    end
  end

  test "準備失敗と不整合ではAの選択と準備を維持する" do
    new_control do
      @client.stub_responses(:get_stage, "AccessDeniedException")
      assert_no_difference "StreamSession.count" do
        switch_to_b
        assert_response :service_unavailable
      end
      assert_equal @a.id, @request.session[:current_booth_id]
      assert_equal @preparation_a.id, @a.reload.current_stream_session_id
      assert_nil @b.reload.current_stream_session_id
      prepare(@b, @other).update!(broadcast_started_at: Time.current)
      switch_to_b
      assert_response :service_unavailable
      assert_equal @a.id, @request.session[:current_booth_id]
    end
  end

  test "モーダル表示後の本人開始と権限喪失を確定前に再確認する" do
    new_control do
      get select_modal_cast_booths_path(source: "header"), headers: { "Turbo-Frame" => "modal" }
      record_publisher(@preparation_a, @actor, :live)
      switch_to_b
      assert_response :conflict
      assert_equal @a.id, @request.session[:current_booth_id]
      assert_empty @client.api_requests
      @preparation_a.update!(ended_at: Time.current, status: :ended)
      @a.update!(status: :offline, current_stream_session: nil)
      StoreMembership.find_by!(store: @b.store, user: @actor).destroy!
      switch_to_b
      assert_response :conflict
      assert_equal @a.id, @request.session[:current_booth_id]
    end
  end

  private

  def switch_to_b
    post cast_current_booth_path, params: { booth_id: @b.id, return_to: live_cast_booth_path(@a) }, as: :json
  end

  def prepare(booth, creator)
    StreamSession.create!(booth: booth, store: booth.store, started_by_cast_user: creator,
      status: :live, started_at: Time.current, title: "保存済み#{booth.name}", ivs_stage_arn: booth.ivs_stage_arn).tap do |stream|
      booth.update!(status: :standby, current_stream_session: stream)
    end
  end

  def record_publisher(stream, actor, status)
    stream.update!(actual_publisher_user: actor, actual_publisher_source: "ivs_verified",
      actual_publisher_recorded_at: Time.current, broadcast_started_at: Time.current)
    stream.booth.update!(status: status)
  end

  def new_control
    original = Aws::IVSRealTime::Client.method(:new)
    client = @client
    Aws::IVSRealTime::Client.define_singleton_method(:new) { |**_options| client }
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") { yield }
  ensure
    Aws::IVSRealTime::Client.define_singleton_method(:new, original)
  end
end
