require "test_helper"
require_relative "../../support/publisher_connection_test_support"

class Cast::BoothManagementTest < ActionDispatch::IntegrationTest
  include PublisherConnectionTestSupport
  include ActionCable::TestHelper

  setup do
    build_publisher_fixture
    sign_in @other_publisher, scope: :user
  end

  %i[store_admin system_admin].each do |role|
    test "#{role}: 情報画面の管理操作と確認対象は配信状態に従う" do
      @other_publisher.update!(role: role)
      with_publisher_client do
        get cast_booth_path(@booth)
        assert_response :ok
        assert_management_buttons(force_end: false, archive: true)
        assert_target_form(archive_admin_booth_path(@booth), generation: 0)
        assert_select "button[data-turbo-confirm]" do |buttons|
          assert buttons.any? { |button| button["data-turbo-confirm"].include?(@store.name) &&
            button["data-turbo-confirm"].include?(@booth.name) && button["data-turbo-confirm"].include?(@stream_session.title) }
        end
        assert_empty @ivs_client.api_requests

        begin_broadcast
        %i[live away].each do |status|
          @booth.update!(status: status)
          get cast_booth_path(@booth)
          assert_response :ok
          assert_management_buttons(force_end: true, archive: false)
          assert_target_form(force_end_admin_booth_path(@booth), generation: 1)
          assert_includes response.body, "先に配信を終了してください"
        end
      end
    end

    test "#{role}: 強制終了後は選択を保ち同じブース情報で閉鎖へ進める" do
      @other_publisher.update!(role: role)
      with_publisher_client do
        begin_broadcast
        2.times do
          post force_end_admin_booth_path(@booth), params: target_params
          assert_redirected_to cast_booth_path(@booth)
          follow_redirect!
          assert_response :ok
          assert_management_buttons(force_end: false, archive: true)
          assert_select "input[name='stream_session_id'][value='']"
          assert_equal @booth.id, @request.session[:current_booth_id]
          assert_equal @store.id, @request.session[:current_store_id]
        end
        assert @stream_session.reload.ended?
        assert_equal @publisher.id, @stream_session.actual_publisher_user_id
        assert_equal 1, disconnect_requests.size
        patch archive_admin_booth_path(@booth), params: { stream_session_id: "" }
        assert_redirected_to cast_booth_path(@booth)
        follow_redirect!
        assert_response :ok
        assert_closed_information
      end
    end
  end

  test "配信準備は強制終了の直接要求を拒否し閉鎖で準備を終了する" do
    with_publisher_client do
      post force_end_admin_booth_path(@booth), params: target_params(generation: 0), as: :json
      assert_response :conflict
      refute @stream_session.reload.ended?
      patch archive_admin_booth_path(@booth), params: target_params(generation: 0)
      assert_redirected_to cast_booth_path(@booth)
      follow_redirect!
      assert_closed_information
      assert @stream_session.reload.ended?
      assert_nil @stream_session.actual_publisher_user_id
      assert_nil @stream_session.broadcast_started_at
      assert_empty disconnect_requests
    end
  end

  test "キャストと権限外管理者は管理操作できず閲覧で準備も切断も行わない" do
    with_publisher_client do
      sign_in @creator, scope: :user
      get cast_booth_path(@booth)
      assert_response :ok
      assert_management_buttons(force_end: false, archive: false)
      assert_select "[data-controller='publisher-disconnect-status']", count: 0
      post force_end_admin_booth_path(@booth), params: target_params, as: :json
      assert_response :forbidden
      patch archive_admin_booth_path(@booth), params: target_params, as: :json
      assert_response :forbidden

      StoreMembership.where(user: @other_publisher).delete_all
      sign_in @other_publisher, scope: :user
      get cast_booth_path(@booth)
      assert_response :forbidden
      post force_end_admin_booth_path(@booth), params: target_params, as: :json
      assert_response :not_found
      patch archive_admin_booth_path(@booth), params: target_params, as: :json
      assert_response :not_found
      assert_empty @ivs_client.api_requests
      refute @booth.reload.archived?
      refute @stream_session.reload.ended?
    end
  end

  test "別店舗へ選択変更した古い管理フォームはどちらのブースも変更しない" do
    with_publisher_client do
      begin_broadcast
      select_booth(@booth)
      other_store = Store.create!(name: "別店舗")
      StoreMembership.create!(store: other_store, user: @other_publisher, membership_role: :admin)
      other_booth = Booth.create!(store: other_store, name: "別ブース")
      select_booth(other_booth)
      post force_end_admin_booth_path(@booth), params: target_params, as: :json
      assert_response :conflict
      assert_equal "selection_mismatch", response.parsed_body["error"]
      patch archive_admin_booth_path(@booth), params: target_params, as: :json
      assert_response :conflict
      assert_equal other_booth.id, @request.session[:current_booth_id]
      assert_equal other_store.id, @request.session[:current_store_id]
      assert @booth.reload.live?
      assert other_booth.reload.offline?
      assert_empty disconnect_requests
    end
  end

  test "古い世代や配信の終了要求は新しい接続を切断しない" do
    with_publisher_client do
      first = begin_broadcast
      second = issue_token(generation: 1)
      post force_end_admin_booth_path(@booth), params: target_params
      assert_redirected_to cast_booth_path(@booth)
      assert_match(/状態が更新/, flash[:alert])
      refute @stream_session.reload.ended?
      assert_equal [ first[:participant_id] ], disconnect_requests.pluck(:participant_id)
      post force_end_admin_booth_path(@booth), params: target_params(generation: 2), as: :json
      assert_response :ok
      next_stream = StreamSession.create!(booth: @booth, store: @store, started_by_cast_user: @creator,
        started_at: Time.current, status: :live, ivs_stage_arn: @booth.ivs_stage_arn)
      @booth.reload.update!(status: :standby, current_stream_session: next_stream)
      post force_end_admin_booth_path(@booth), params: target_params(generation: 2), as: :json
      assert_response :ok
      patch archive_admin_booth_path(@booth), params: target_params(generation: 2), as: :json
      assert_response :conflict
      assert_equal next_stream.id, @booth.reload.current_stream_session_id
      refute next_stream.reload.ended?
      refute @booth.archived?
      assert_equal [ first[:participant_id], second[:participant_id] ], disconnect_requests.pluck(:participant_id)
    end
  end

  test "不整合の情報は操作を表示せず直接要求も拒否する" do
    with_publisher_client do
      @booth.update!(status: :offline)
      get cast_booth_path(@booth)
      assert_response :ok
      assert_management_buttons(force_end: false, archive: false)
      assert_includes response.body, "ブースの配信状態を確認できません"
      patch archive_admin_booth_path(@booth), params: target_params(generation: 0), as: :json
      assert_response :conflict
      @booth.update!(status: :live)
      get cast_booth_path(@booth)
      assert_management_buttons(force_end: false, archive: false)
      post force_end_admin_booth_path(@booth), params: target_params(generation: 0), as: :json
      assert_response :service_unavailable
      refute @stream_session.reload.ended?
      refute @booth.reload.archived?
      assert_empty @ivs_client.api_requests
    end
  end

  test "他者の取消による切断待ちも対象情報に表示し上限後はエラーになる" do
    with_publisher_client do
      issued = issue_token
      @ivs_client.stub_responses(:disconnect_participant, "AccessDeniedException")
      cancel_token(issued)
      connection = @stream_session.reload.current_publisher_connection
      get cast_booth_path(@booth)
      assert_response :ok
      assert_disconnect_state("retrying")
      assert_management_buttons(force_end: false, archive: true)
      channel = Turbo::StreamsChannel.send(:stream_name_from, [ @booth, :publisher_disconnect ])
      notifications = capture_broadcasts(channel) { StreamSessionNotifier.broadcast_publisher_disconnect(connection) }
      assert_equal 1, notifications.size
      fragment = Nokogiri::HTML.fragment(notifications.first)
      status_element = fragment.at_css("#publisher_disconnect_booth_#{@booth.id}")
      assert_equal "retrying", status_element["data-publisher-disconnect-status-state-value"]
      assert_equal publisher_disconnect_state_cast_booth_path(@booth, scope: "booth"), status_element["data-publisher-disconnect-status-url-value"]
      3.times do
        travel_to(connection.reload.next_disconnect_retry_at, with_usec: true) { DisconnectPublisherConnectionJob.perform_now(connection.id) }
      end
      2.times do
        get cast_booth_path(@booth)
        assert_disconnect_state("failed")
        assert_select ".alert-danger", text: /運用担当者へお問い合わせください/
        get publisher_disconnect_state_cast_booth_path(@booth, scope: "booth"), as: :json
        assert_equal "failed", response.parsed_body["disconnect_state"]
      end
      assert_equal 4, disconnect_requests.size
      assert_equal 4, connection.reload.disconnect_attempts
      patch archive_admin_booth_path(@booth), params: target_params(generation: @stream_session.reload.publisher_generation)
      assert_redirected_to cast_booth_path(@booth)
      follow_redirect!
      assert_closed_information
      assert_disconnect_state("failed")
    end
  ensure
    ErrorLog.where(stream_session_id: @stream_session.id).delete_all
  end

  test "本人の別ブースだけに切断待ちがあっても表示対象を失敗とせず開始制限は維持する" do
    with_publisher_client do
      issued = issue_token
      @ivs_client.stub_responses(:disconnect_participant, "AccessDeniedException")
      cancel_token(issued)
      other_booth = build_prepared_booth("情報確認先")
      sign_in @publisher, scope: :user
      select_booth(other_booth)
      get cast_booth_path(other_booth)
      assert_response :ok
      assert_disconnect_state("disconnected")
      assert_select "[data-controller='publisher-disconnect-status'].d-none"
      get publisher_disconnect_state_cast_booth_path(other_booth, scope: "booth"), as: :json
      assert_equal "disconnected", response.parsed_body["disconnect_state"]
      get publisher_disconnect_state_cast_booth_path(other_booth), as: :json
      assert_equal "retrying", response.parsed_body["disconnect_state"]
      assert Ivs::RetryPublisherDisconnectsService.pending(booth: other_booth, actor: @publisher).exists?
      assert_equal 1, disconnect_requests.size

      StoreMembership.where(user: @publisher).delete_all
      get publisher_disconnect_state_cast_booth_path(@booth, scope: "booth"), as: :json
      assert_response :forbidden
    end
  end

  test "再接続取消の切断待ちと配信中が併存しても強制終了して閉鎖できる" do
    with_publisher_client do
      begin_broadcast
      reconnect = issue_token(generation: 1)
      @ivs_client.stub_responses(:disconnect_participant, "AccessDeniedException")
      cancel_token(reconnect)
      get cast_booth_path(@booth)
      assert_response :ok
      assert_disconnect_state("retrying")
      assert_management_buttons(force_end: true, archive: false)
      post force_end_admin_booth_path(@booth), params: target_params(generation: @stream_session.reload.publisher_generation)
      assert_redirected_to cast_booth_path(@booth)
      assert_match(/終了と未消化ドリンクの返却は完了/, flash[:notice])
      follow_redirect!
      assert_disconnect_state("retrying")
      assert_management_buttons(force_end: false, archive: true)
      patch archive_admin_booth_path(@booth), params: { stream_session_id: "" }
      assert_redirected_to cast_booth_path(@booth)
      follow_redirect!
      assert_closed_information
      assert_disconnect_state("retrying")
    end
  end

  private

  def begin_broadcast
    issued = issue_token
    stub_published_participant(issued)
    confirm_token(issued)
    issued
  end

  def select_booth(booth)
    post cast_current_booth_path, params: { booth_id: booth.id, source: "header", return_to_key: "booth_show" }, as: :json
    assert_response :ok
    assert_equal booth.id, @request.session[:current_booth_id]
  end

  def target_params(generation: 1)
    { stream_session_id: @stream_session.id.to_s, generation: generation }
  end

  def assert_management_buttons(force_end:, archive:)
    assert_select "form[action=?]", force_end_admin_booth_path(@booth), count: force_end ? 1 : 0
    assert_select "form[action=?]", archive_admin_booth_path(@booth), count: archive ? 1 : 0
    assert_select ".booth-show button", text: /再確認|切断を再試行/, count: 0
  end

  def assert_target_form(path, generation:)
    assert_select "form[action=?]", path do
      assert_select "input[name='stream_session_id'][value='#{@stream_session.id}']"
      assert_select "input[name='generation'][value='#{generation}']"
    end
  end

  def assert_disconnect_state(state)
    assert_select "[data-controller='publisher-disconnect-status'][data-publisher-disconnect-status-state-value='#{state}']"
    assert_select ".booth-show button", text: /再確認|切断を再試行/, count: 0
  end

  def assert_closed_information
    assert_select ".badge", text: "閉鎖済み"
    assert_select "a[href=?]", cast_booth_stream_sessions_path(@booth)
    assert_select "a[href=?]", edit_cast_booth_path(@booth), count: 0
    assert_select "#booth-share-modal", count: 0
    assert_management_buttons(force_end: false, archive: false)
    assert_equal @booth.id, @request.session[:current_booth_id]
    assert_equal @store.id, @request.session[:current_store_id]
  end
end
