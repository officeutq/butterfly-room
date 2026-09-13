require "test_helper"

class IvsParticipantTokensTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    StreamSessions::IvsParticipantTokensController::GUEST_VIEWER_RATE_LIMIT_STORE.clear

    # --- users ---
    @cast     = User.create!(email: "cast@example.com",     password: "password", role: :cast)
    @customer = User.create!(email: "cust@example.com",     password: "password", role: :customer)
    @admin    = User.create!(email: "admin@example.com",    password: "password", role: :store_admin)

    # --- store / booth / session ---
    @store = create_store!
    @booth = create_booth!(store: @store, status: :live)

    @session = StreamSession.create!(
      booth: @booth,
      store: @store,
      status: :live,
      started_at: Time.current,
      started_by_cast_user: @cast,
      ivs_stage_arn: "arn:aws:ivsrealtime:ap-northeast-1:123456789012:stage/abcdEFGHijklMNOP"
    )

    @booth.update!(current_stream_session: @session, status: :live)

    # cast を booth に紐付け
    BoothCast.create!(booth: @booth, cast_user: @cast)
  end

  test "publisher: cast in booth can get token" do
    sign_in @cast, scope: :user

    stub_ivs_token("PUB_TOKEN") do
      post stream_session_ivs_participant_tokens_path(@session),
          params: { role: "publisher" }.to_json,
          headers: json_headers
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "publisher", body["role"]
    assert_equal @session.ivs_stage_arn, body["ivs_stage_arn"]
    assert_equal "PUB_TOKEN", body["participant_token"]
  end

  test "viewer: customer not banned can get token" do
    sign_in @customer, scope: :user

    stub_ivs_token("VIEW_TOKEN") do
      post stream_session_ivs_participant_tokens_path(@session),
          params: { role: "viewer" }.to_json,
          headers: json_headers
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "viewer", body["role"]
    assert_equal "VIEW_TOKEN", body["participant_token"]
  end

  test "viewer: guest can get subscribe-only token without user_id attribute" do
    stub_ivs_token("GUEST_VIEW_TOKEN") do |requests|
      post stream_session_ivs_participant_tokens_path(@session),
           params: { role: "viewer" }.to_json,
           headers: json_headers

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal "viewer", body["role"]
      assert_equal "GUEST_VIEW_TOKEN", body["participant_token"]

      request = requests.fetch(0)
      assert_equal [ "SUBSCRIBE" ], request[:capabilities]
      assert_equal "viewer", request[:attributes]["role"]
      assert_equal @session.id.to_s, request[:attributes]["stream_session_id"]
      assert_not request[:attributes].key?("user_id")
    end
  end

  test "viewer: guest cannot get token for an unpublished or archived booth" do
    @store.update!(published: false)

    post stream_session_ivs_participant_tokens_path(@session),
         params: { role: "viewer" }.to_json,
         headers: json_headers

    assert_response :not_found

    @store.update!(published: true)
    @booth.update!(archived_at: Time.current)

    post stream_session_ivs_participant_tokens_path(@session),
         params: { role: "viewer" }.to_json,
         headers: json_headers

    assert_response :not_found
  end

  test "viewer: guest remains subject to joinable and stage-bound checks" do
    @booth.update!(status: :standby)

    post stream_session_ivs_participant_tokens_path(@session),
         params: { role: "viewer" }.to_json,
         headers: json_headers

    assert_response :conflict
    assert_equal "not_joinable", JSON.parse(response.body)["error"]

    @booth.update!(status: :live, current_stream_session: nil)

    post stream_session_ivs_participant_tokens_path(@session),
         params: { role: "viewer" }.to_json,
         headers: json_headers

    assert_response :conflict
    assert_equal "not_joinable", JSON.parse(response.body)["error"]

    @booth.update!(current_stream_session: @session)
    @session.update!(ivs_stage_arn: nil)

    post stream_session_ivs_participant_tokens_path(@session),
         params: { role: "viewer" }.to_json,
         headers: json_headers

    assert_response :conflict
    assert_equal "stage_not_bound", JSON.parse(response.body)["error"]
  end

  test "publisher: guest remains unauthenticated" do
    post stream_session_ivs_participant_tokens_path(@session),
         params: { role: "publisher" }.to_json,
         headers: json_headers

    assert_response :unauthorized
  end

  test "viewer: guest token requests are rate limited per session" do
    stub_ivs_token("RATE_LIMITED_GUEST_VIEW_TOKEN") do
      30.times do
        post stream_session_ivs_participant_tokens_path(@session),
             params: { role: "viewer" }.to_json,
             headers: json_headers
        assert_response :success
      end

      post stream_session_ivs_participant_tokens_path(@session),
           params: { role: "viewer" }.to_json,
           headers: json_headers

      assert_response :too_many_requests
      assert_equal "rate_limited", JSON.parse(response.body)["error"]
    end
  end

  test "viewer: cast can get token" do
    sign_in @cast, scope: :user

    stub_ivs_token("CAST_VIEW_TOKEN") do
      post stream_session_ivs_participant_tokens_path(@session),
          params: { role: "viewer" }.to_json,
          headers: json_headers
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "viewer", body["role"]
    assert_equal @session.ivs_stage_arn, body["ivs_stage_arn"]
    assert_equal "CAST_VIEW_TOKEN", body["participant_token"]
  end

  test "publisher: cast role but not in booth_casts is forbidden" do
    other_cast = User.create!(email: "other_cast@example.com", password: "password", role: :cast)
    sign_in other_cast, scope: :user

    # AWS が呼ばれないことも保証したいので、stubは置かない（呼ばれたら例外になるよう後述のstub方式でもOK）
    post stream_session_ivs_participant_tokens_path(@session),
         params: { role: "publisher" }.to_json,
         headers: json_headers

    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "forbidden", body["error"]
  end

  test "viewer: banned customer is forbidden" do
    StoreBan.create!(
      store: @store,
      customer_user: @customer,
      reason: "test",
      created_by_store_admin_user: @admin,
      created_at: Time.current
    )

    sign_in @customer, scope: :user

    post stream_session_ivs_participant_tokens_path(@session),
         params: { role: "viewer" }.to_json,
         headers: json_headers

    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "forbidden", body["error"]
  end

  test "viewer: revoked ban does not forbid customer" do
    StoreBan.create!(
      store: @store,
      customer_user: @customer,
      reason: "test",
      created_by_store_admin_user: @admin,
      revoked_at: Time.current,
      revoked_by_user: @admin
    )

    sign_in @customer, scope: :user

    stub_ivs_token("VIEW_TOKEN_AFTER_REVOKE") do
      post stream_session_ivs_participant_tokens_path(@session),
          params: { role: "viewer" }.to_json,
          headers: json_headers
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "VIEW_TOKEN_AFTER_REVOKE", body["participant_token"]
  end

  test "invalid role returns 422" do
    sign_in @customer, scope: :user

    post stream_session_ivs_participant_tokens_path(@session),
         params: { role: "hacker" }.to_json,
         headers: json_headers

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal "invalid_role", body["error"]
  end

  test "not_joinable returns 409 when booth is offline (publisher)" do
    # ensure を走らせないために joinable を崩す（validate_joinable! で 409）
    @booth.update!(status: :offline)

    sign_in @cast, scope: :user

    post stream_session_ivs_participant_tokens_path(@session),
         params: { role: "publisher" }.to_json,
         headers: json_headers

    assert_response :conflict
    body = JSON.parse(response.body)
    assert_equal "not_joinable", body["error"]
  end

  test "not_joinable returns 409 when booth current_stream_session mismatches" do
    @booth.update!(current_stream_session: nil)

    sign_in @customer, scope: :user

    post stream_session_ivs_participant_tokens_path(@session),
         params: { role: "viewer" }.to_json,
         headers: json_headers

    assert_response :conflict
    body = JSON.parse(response.body)
    assert_equal "not_joinable", body["error"]
  end

  test "publisher: store_admin of booth store can get token" do
    StoreMembership.create!(store: @store, user: @admin, membership_role: :admin)
    sign_in @admin, scope: :user

    stub_ivs_token("ADMIN_PUB_TOKEN") do
      post stream_session_ivs_participant_tokens_path(@session),
          params: { role: "publisher" }.to_json,
          headers: json_headers
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "publisher", body["role"]
    assert_equal "ADMIN_PUB_TOKEN", body["participant_token"]
  end

  test "publisher: assigned cast can get token for an unpublished store" do
    @store.update!(published: false)
    sign_in @cast, scope: :user

    stub_ivs_token("HIDDEN_CAST_PUB_TOKEN") do
      post stream_session_ivs_participant_tokens_path(@session),
           params: { role: "publisher" }.to_json,
           headers: json_headers
    end

    assert_response :success
    assert_equal "HIDDEN_CAST_PUB_TOKEN", JSON.parse(response.body)["participant_token"]
  end

  test "publisher: store admin can get token for an unpublished store" do
    @store.update!(published: false)
    StoreMembership.create!(store: @store, user: @admin, membership_role: :admin)
    sign_in @admin, scope: :user

    stub_ivs_token("HIDDEN_ADMIN_PUB_TOKEN") do
      post stream_session_ivs_participant_tokens_path(@session),
           params: { role: "publisher" }.to_json,
           headers: json_headers
    end

    assert_response :success
    assert_equal "HIDDEN_ADMIN_PUB_TOKEN", JSON.parse(response.body)["participant_token"]
  end

  test "publisher: unrelated cast is forbidden for an unpublished store" do
    @store.update!(published: false)
    other_cast = User.create!(email: "hidden-other-cast@example.com", password: "password", role: :cast)
    sign_in other_cast, scope: :user

    post stream_session_ivs_participant_tokens_path(@session),
         params: { role: "publisher" }.to_json,
         headers: json_headers

    assert_response :forbidden
    assert_equal "forbidden", JSON.parse(response.body)["error"]
  end

  private

  def json_headers
    { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
  end

  def create_store!
    Store.create!(name: "Test Store", published: true)
  end

  def create_booth!(store:, status:)
    Booth.create!(store: store, name: "Test Booth", status: status)
  end

  # AWS IVS RealTime クライアントをスタブして token を返す
  def stub_ivs_token(token)
    requests = []
    participant_token = Struct.new(:token, :expiration_time).new(token, Time.current + 15.minutes)
    resp = Struct.new(:participant_token).new(participant_token)

    original = Aws::IVSRealTime::Client

    fake_client_class = Class.new do
      define_method(:initialize) { |*| }
      define_method(:create_participant_token) do |**kwargs|
        requests << kwargs
        resp
      end
    end

    Aws::IVSRealTime.send(:remove_const, :Client)
    Aws::IVSRealTime.const_set(:Client, fake_client_class)

    yield requests
  ensure
    Aws::IVSRealTime.send(:remove_const, :Client) rescue nil
    Aws::IVSRealTime.const_set(:Client, original) if defined?(original) && original
  end
end
