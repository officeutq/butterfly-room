require "test_helper"

class CastInvitationBroadcastGuardTest < ActionDispatch::IntegrationTest
  setup do
    @store = Store.create!(name: "Current invitation guard")
    @target_store = Store.create!(name: "Invited store")
    @actor = User.create!(email: "invitation-broadcast@example.com", password: "password", role: :cast,
      phone_number: "+819012345678", phone_verified_at: Time.current)
    @other = User.create!(email: "invitation-other@example.com", password: "password", role: :store_admin)
    [ @store, @target_store ].each { |store| StoreMembership.create!(store: store, user: @other, membership_role: :admin) }
    @booth = Booth.create!(store: @store, name: "Current booth", status: :standby, ivs_stage_arn: "guard-stage")
    BoothCast.create!(booth: @booth, cast_user: @actor)
    @stream_session = StreamSession.create!(booth: @booth, store: @store, started_by_cast_user: @other,
      status: :live, started_at: 10.minutes.ago)
    @booth.update!(current_stream_session: @stream_session)
    issued = StoreCastInvitations::IssueInvitation.call!(store: @target_store, invited_by_user: @other)
    @invitation = issued.invitation
    @token = issued.token
    @stage_calls = []
    calls = @stage_calls
    fake_ivs = Object.new
    fake_ivs.define_singleton_method(:create_stage!) do |name:, tags: {}|
      calls << [ name, tags ]
      "arn:aws:ivs:ap-northeast-1:123456789012:stage/#{name}"
    end
    Ivs::Client.factory = ->(region:) { fake_ivs }
    @previous_fake_ivs = ENV["MANUAL_CAPTURE_FAKE_IVS"]
    ENV["MANUAL_CAPTURE_FAKE_IVS"] = "0"
  end

  teardown do
    Ivs::Client.reset_factory!
    Sms::Client.reset_factory!
    @previous_fake_ivs.nil? ? ENV.delete("MANUAL_CAPTURE_FAKE_IVS") : ENV["MANUAL_CAPTURE_FAKE_IVS"] = @previous_fake_ivs
  end

  test "配信中と離席中は承認ボタンを出さず直接承認も拒否して選択と配信を維持する" do
    select_current_booth
    record_broadcast
    %i[live away].each do |status|
      @booth.update!(status: status)
      before = @stream_session.reload.attributes
      assert_no_difference [ "Booth.count", "BoothCast.count", "StoreMembership.count" ] do
        get cast_invitation_path(@token)
        assert_blocked_page("配信を終了してから招待を承認してください")
        post accept_cast_invitation_path(@token)
        assert_redirected_to cast_invitation_path(@token)
      end
      assert_not @invitation.reload.used?
      assert_empty @stage_calls
      assert_equal @booth.id, @request.session[:current_booth_id]
      assert_equal @store.id, @request.session[:current_store_id]
      assert_equal before, @stream_session.reload.attributes
    end
  end

  test "確認画面の後に別タブで開始した状態でも承認直前に拒否する" do
    select_current_booth
    get cast_invitation_path(@token)
    assert_select "form[action='#{accept_cast_invitation_path(@token)}']", count: 1
    record_broadcast
    assert_no_difference [ "Booth.count", "BoothCast.count", "StoreMembership.count" ] do
      post accept_cast_invitation_path(@token)
      assert_redirected_to cast_invitation_path(@token)
    end
    assert_not @invitation.reload.used?
    assert_empty @stage_calls
  end

  test "準備と初回開始権だけなら承認でき既存の準備と接続を変更しない" do
    select_current_booth
    connection = StreamPublisherConnection.create!(stream_session: @stream_session, booth: @booth, user: @actor,
      generation: 1, request_id: SecureRandom.uuid, ivs_stage_arn: @booth.ivs_stage_arn,
      ivs_participant_id: "pending-participant", token_expires_at: 1.hour.from_now)
    @stream_session.update!(current_publisher_connection: connection, publisher_generation: 1)
    before = @stream_session.attributes
    get cast_invitation_path(@token)
    assert_select "form[action='#{accept_cast_invitation_path(@token)}']", count: 1
    assert_difference "Booth.count", 1 do
      post accept_cast_invitation_path(@token)
    end
    assert @invitation.reload.used?
    assert_equal 1, @stage_calls.size
    assert_equal before, @stream_session.reload.attributes
    assert_nil connection.reload.released_at
    assert_nil connection.disconnect_requested_at
  end

  test "準備を作った本人でも別人が配信していれば招待承認を禁止しない" do
    select_current_booth
    @stream_session.update!(started_by_cast_user: @actor)
    record_broadcast(publisher: @other)
    assert_difference "Booth.count", 1 do
      post accept_cast_invitation_path(@token)
    end
    assert @invitation.reload.used?
    assert_equal @other.id, @stream_session.reload.actual_publisher_user_id
  end

  test "本人の配信状態が不整合なら承認を保留する" do
    select_current_booth
    record_broadcast
    @booth.update!(current_stream_session: nil)
    get cast_invitation_path(@token)
    assert_blocked_page("配信状態を確認できません")
    assert_no_difference [ "Booth.count", "BoothCast.count", "StoreMembership.count" ] do
      post accept_cast_invitation_path(@token)
    end
    assert_redirected_to cast_invitation_path(@token)
    assert_not @invitation.reload.used?
    assert_empty @stage_calls
  end

  test "既に所属済みでも配信中は表示によって招待を消費せず終了後だけ消費する" do
    select_current_booth
    StoreMembership.create!(store: @target_store, user: @actor, membership_role: :cast)
    record_broadcast
    get cast_invitation_path(@token)
    assert_blocked_page("配信を終了してから招待を承認してください")
    assert_not @invitation.reload.used?
    end_broadcast
    assert_no_difference [ "Booth.count", "BoothCast.count", "StoreMembership.count" ] do
      get cast_invitation_path(@token)
    end
    assert @invitation.reload.used?
    assert_includes response.body, "この店舗にはすでにキャストとして登録されています"
    assert_empty @stage_calls
    assert_equal @booth.id, @request.session[:current_booth_id]
  end

  test "既に所属済みの直接承認は重複したブースを作らず案内へ戻す" do
    select_current_booth
    StoreMembership.create!(store: @target_store, user: @actor, membership_role: :cast)
    assert_no_difference [ "Booth.count", "BoothCast.count", "StoreMembership.count" ] do
      post accept_cast_invitation_path(@token)
      assert_redirected_to cast_invitation_path(@token)
      follow_redirect!
    end
    assert @invitation.reload.used?
    assert_empty @stage_calls
    assert_equal @booth.id, @request.session[:current_booth_id]
  end

  test "配信終了後は同じ招待を再確認して通常どおり承認できる" do
    select_current_booth
    record_broadcast
    post accept_cast_invitation_path(@token)
    assert_not @invitation.reload.used?
    end_broadcast
    get cast_invitation_path(@token)
    assert_select "form[action='#{accept_cast_invitation_path(@token)}']", count: 1
    post accept_cast_invitation_path(@token)
    assert @invitation.reload.used?
    assert_equal 1, @stage_calls.size
  end

  test "通常ログインは成立させ招待へ戻ると本人配信による制限を表示する" do
    record_broadcast
    get cast_invitation_path(@token)
    post user_session_path, params: { user: { email: @actor.email, password: "password" } }
    assert_redirected_to cast_invitation_path(@token)
    follow_redirect!
    assert_blocked_page("配信を終了してから招待を承認してください")
    get edit_profile_path
    assert_response :success
    assert_not @invitation.reload.used?
  end

  test "SMSログインでも招待へ戻ると本人配信による制限を表示する" do
    record_broadcast
    deliveries = []
    fake_sms = Object.new
    fake_sms.define_singleton_method(:publish!) { |phone_number:, message:| deliveries << message }
    Sms::Client.factory = ->(region:) { fake_sms }
    with_env("SMS_DELIVERY_MODE" => "live") do
      get cast_invitation_path(@token)
      post phone_session_path, params: { phone_number: "09012345678" }
      assert_redirected_to confirm_phone_session_path
      post verify_phone_session_path, params: { otp_code: deliveries.last[/\d{6}/] }
      assert_redirected_to cast_invitation_path(@token)
      follow_redirect!
      assert_blocked_page("配信を終了してから招待を承認してください")
    end
    assert_not @invitation.reload.used?
  end

  private

  def select_current_booth
    sign_in @actor
    post cast_current_booth_path, params: { booth_id: @booth.id, return_to_key: "booth_show" }
    assert_response :redirect
  end

  def record_broadcast(publisher: @actor)
    @stream_session.update!(actual_publisher_user: publisher, actual_publisher_source: "ivs_verified",
      actual_publisher_recorded_at: Time.current, broadcast_started_at: 5.minutes.ago)
    @booth.update!(status: :live)
  end

  def end_broadcast
    @stream_session.update!(status: :ended, ended_at: Time.current)
    @booth.update!(status: :offline, current_stream_session: nil)
  end

  def assert_blocked_page(message)
    assert_response :success
    assert_includes response.body, message
    assert_select "form[action='#{accept_cast_invitation_path(@token)}']", count: 0
  end
end
