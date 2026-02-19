require "test_helper"

class IvsParticipantTokensTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
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

  private

  def json_headers
    { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
  end

  def create_store!
    Store.create!(name: "Test Store")
  end

  def create_booth!(store:, status:)
    Booth.create!(store: store, name: "Test Booth", status: status)
  end

  # AWS IVS RealTime クライアントをスタブして token を返す
  def stub_ivs_token(token)
    participant_token = Struct.new(:token, :expiration_time).new(token, Time.current + 15.minutes)
    resp = Struct.new(:participant_token).new(participant_token)

    original = Aws::IVSRealTime::Client

    fake_client_class = Class.new do
      define_method(:initialize) { |*| }
      define_method(:create_participant_token) { |**_kwargs| resp }
    end

    Aws::IVSRealTime.send(:remove_const, :Client)
    Aws::IVSRealTime.const_set(:Client, fake_client_class)

    yield
  ensure
    Aws::IVSRealTime.send(:remove_const, :Client) rescue nil
    Aws::IVSRealTime.const_set(:Client, original) if defined?(original) && original
  end
end
