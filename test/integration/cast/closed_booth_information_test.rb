require "test_helper"
require_relative "../../support/publisher_connection_test_support"

class Cast::ClosedBoothInformationTest < ActionDispatch::IntegrationTest
  include PublisherConnectionTestSupport

  setup do
    build_publisher_fixture
    @creator.update!(display_name: "担当キャスト")
    @publisher.update!(display_name: "実際の配信者")
    @stream_session.update!(status: :ended, ended_at: 1.minute.ago, broadcast_started_at: 5.minutes.ago,
      actual_publisher_user: @publisher, actual_publisher_source: "ivs_verified", actual_publisher_recorded_at: 5.minutes.ago)
    @booth.update!(status: :offline, current_stream_session: nil, archived_at: Time.current)
    @active = build_prepared_booth("現在の担当ブース")
  end

  %i[cast store_admin system_admin].each do |role|
    test "#{role}: 閉鎖済みの情報・履歴・結果は同じ対象で閲覧でき選択と記録を変えない" do
      with_publisher_client do
        sign_in_role(role)
        selected = role == :cast ? @active : @booth
        select_booth(selected)
        before = [ @stream_session.reload.attributes, @booth.reload.attributes, @active.reload.attributes ]
        get cast_booth_path(@booth)
        assert_response :ok
        assert_closed_information
        assert_select ".booth-show-info", text: /担当キャスト/

        get cast_booth_stream_sessions_path(@booth)
        assert_response :ok
        assert_select "a[href=?]", cast_stream_session_path(@stream_session), text: /実際の配信者/
        return_url = css_select("a").find { |link| link.text == "ブース情報へ戻る" }["href"]
        get return_url
        assert_response :ok
        assert_closed_information
        get cast_stream_session_path(@stream_session)
        assert_response :ok
        assert_select ".card-body", text: /実際の配信者/
        assert_selection(selected)
        assert_equal before, [ @stream_session.reload.attributes, @booth.reload.attributes, @active.reload.attributes ]
        assert_empty @ivs_client.api_requests
      end
    end

    test "#{role}: 閉鎖済みの編集と共有は古いフォームや直接要求でも拒否する" do
      with_publisher_client do
        sign_in_role(role)
        select_booth(role == :cast ? @active : @booth)
        before = @booth.reload.attributes
        [ edit_cast_booth_path(@booth), share_cast_stream_session_path(@stream_session),
          share_booth_path(@booth), share_booth_path(@booth, stream: @stream_session.id),
          share_ogp_image_booth_path(@booth, format: :jpg) ].each do |path|
          get path
          assert_response :not_found
          assert_select "[data-share-provider]", count: 0
        end
        patch cast_booth_path(@booth), params: { booth: { name: "閉鎖後の変更" } }, as: :json
        assert_response :not_found
        assert_equal before, @booth.reload.attributes
        assert_empty @ivs_client.api_requests
      end
    end

    test "#{role}: 履歴0件の閉鎖済み情報でも切断状態に応じて履歴を閲覧できる" do
      with_publisher_client do
        sign_in_role(role)
        # 終了していない準備だけなので履歴は0件。閉鎖前の取消による切断待ちを表す。
        empty = build_prepared_booth("履歴のない閉鎖済みブース")
        empty.update!(status: :offline, current_stream_session: nil, archived_at: Time.current)
        session = empty.stream_sessions.sole
        connection = StreamPublisherConnection.create!(booth: empty, stream_session: session, user: @publisher,
          request_id: SecureRandom.uuid, generation: 1, ivs_stage_arn: empty.ivs_stage_arn)
        select_booth(role == :cast ? @active : empty)
        %w[disconnected retrying failed].each do |state|
          if state != "disconnected"
            connection.update!(disconnect_requested_at: Time.current, disconnect_reason: "cancel",
              disconnect_attempts: state == "failed" ? 4 : 1, disconnect_failed_at: state == "failed" ? Time.current : nil)
          end
          before = connection.reload.attributes
          get cast_booth_path(empty)
          assert_response :ok
          assert_closed_information(empty)
          if role == :cast
            assert_select "[data-controller='publisher-disconnect-status']", count: 0
          else
            assert_select "[data-publisher-disconnect-status-state-value=?]", state
            assert_select "[data-controller='publisher-disconnect-status'].d-none", count: state == "disconnected" ? 1 : 0
            assert_select "[data-controller='publisher-disconnect-status'].alert-danger", count: state == "failed" ? 1 : 0
            get publisher_disconnect_state_cast_booth_path(empty, scope: "booth"), as: :json
            assert_response :ok
            assert_equal state, response.parsed_body["disconnect_state"]
          end
          get cast_booth_stream_sessions_path(empty)
          assert_response :ok
          assert_select ".alert", text: /配信履歴はまだありません/
          assert_select "a[href=?]", cast_booth_path(empty), text: "ブース情報へ戻る"
          assert_selection(role == :cast ? @active : empty)
          assert_equal before, connection.reload.attributes
        end
        assert_empty @ivs_client.api_requests
      end
    end
  end

  test "キャストは有効な候補が0件でも閉鎖済み情報を閲覧でき選択には登録しない" do
    with_publisher_client do
      sign_in_role(:cast)
      @active.update!(archived_at: Time.current)
      get cast_booth_path(@booth)
      assert_response :ok
      assert_closed_information
      assert_nil @request.session[:current_booth_id]
      post cast_current_booth_path, params: { booth_id: @booth.id, source: "header" }, as: :json
      assert_response :conflict
      assert_nil @request.session[:current_booth_id]
      get live_cast_booth_path(@booth)
      assert_response :not_found
      post cast_booth_stream_sessions_path(@booth)
      assert_response :not_found
      assert_empty @ivs_client.api_requests
    end
  end

  test "権限のないキャスト・店舗管理者・視聴者へ閉鎖済み情報を公開しない" do
    with_publisher_client do
      %i[cast store_admin customer].each do |role|
        actor = User.create!(email: "closed-outsider-#{role}@example.com", password: "password", role: role)
        sign_in actor, scope: :user
        [ cast_booth_path(@booth), cast_booth_stream_sessions_path(@booth),
          cast_stream_session_path(@stream_session), share_cast_stream_session_path(@stream_session) ].each do |path|
          get path
          assert_response :forbidden
          assert_not_includes response.body, @booth.name
        end
        sign_out actor
      end
      get cast_booth_path(@booth)
      assert_redirected_to new_user_session_path
      [ booth_path(@booth), share_booth_path(@booth), share_booth_path(@booth, stream: @stream_session.id) ].each do |path|
        get path
        assert_response :not_found
      end
    end
  end

  private

  def sign_in_role(role)
    @actor = role == :cast ? @creator : @other_publisher
    @actor.update!(role: role)
    sign_in @actor, scope: :user
  end

  def select_booth(booth)
    post cast_current_booth_path, params: { booth_id: booth.id, return_to_key: "booth_show", source: "header" }, as: :json
    assert_response :ok
    assert_selection(booth)
  end

  def assert_selection(booth)
    assert_equal booth.id, @request.session[:current_booth_id]
    assert_equal booth.store_id, @request.session[:current_store_id]
  end

  def assert_closed_information(booth = @booth)
    assert_select ".booth-show .badge", text: "閉鎖済み"
    assert_select ".booth-show-actions a", count: 1
    assert_select ".booth-show-actions a[href=?]", cast_booth_stream_sessions_path(booth)
    assert_select ".booth-show button, .booth-management-actions, #booth-share-modal, [data-share-provider]", count: 0
  end
end
