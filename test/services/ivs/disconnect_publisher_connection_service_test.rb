require "test_helper"
require_relative "../../support/publisher_connection_test_support"

class Ivs::DisconnectPublisherConnectionServiceTest < ActiveSupport::TestCase
  include PublisherConnectionTestSupport
  include ActiveJob::TestHelper
  setup { build_publisher_fixture }

  teardown do
    ErrorLog.where(stream_session_id: @stream_session.id).delete_all
  end

  test "初回と各再試行で成功した場合は保存した参加者だけ解放する" do
    (0..3).each do |failure_count|
      with_publisher_client do
        issued = issue_token(generation: @stream_session.reload.publisher_generation)
        @ivs_client.stub_responses(:disconnect_participant, [ *Array.new(failure_count, "AccessDeniedException"), {} ])
        before = disconnect_requests.size
        cancel_token(issued)
        connection = StreamPublisherConnection.find_by!(request_id: issued[:request_id])
        failure_count.times do
          assert_equal "retrying", connection.reload.disconnect_state
          travel_to(connection.next_disconnect_retry_at, with_usec: true) do
            DisconnectPublisherConnectionJob.perform_now(connection.id)
          end
        end
        assert_equal "disconnected", connection.reload.disconnect_state
        assert_equal failure_count + 1, connection.disconnect_attempts
        assert_equal failure_count + 1, disconnect_requests.size - before
        assert_nil connection.disconnect_failed_at
        assert_nil connection.next_disconnect_retry_at
      end
    end
  end

  test "追加3回の間隔を守り上限後は旧APIや回収でも再実行せずerrorログを1件残す" do
    with_publisher_client do
      issued = issue_token
      @ivs_client.stub_responses(:disconnect_participant, "AccessDeniedException")
      cancel_token(issued)
      connection = StreamPublisherConnection.find_by!(request_id: issued[:request_id])
      [ 0.5, 1, 2 ].each do |delay|
        connection.reload
        assert_in_delta delay, connection.next_disconnect_retry_at - connection.updated_at, 0.02
        count = disconnect_requests.size
        3.times { Ivs::RetryPublisherDisconnectsService.new(booth: @booth, actor: @publisher).call }
        assert_equal count, disconnect_requests.size
        travel_to(connection.next_disconnect_retry_at, with_usec: true) do
          DisconnectPublisherConnectionJob.perform_now(connection.id)
        end
      end
      assert_equal "failed", connection.reload.disconnect_state
      assert_nil connection.released_at
      assert_nil connection.disconnected_at
      assert_nil connection.next_disconnect_retry_at
      assert connection.disconnect_failed_at
      3.times do
        DisconnectPublisherConnectionJob.perform_now(connection.id)
        Ivs::RetryPublisherDisconnectsService.new(booth: @booth, actor: @publisher).call
        assert_raises(StreamSessions::PublisherControl::Error) { issue_token(generation: 2) }
      end
      assert_no_enqueued_jobs(only: DisconnectPublisherConnectionJob) { RetryPendingPublisherDisconnectsJob.perform_now }
      assert_equal 4, disconnect_requests.size
      logs = ErrorLog.where(request_id: issued[:request_id])
      assert_equal 1, logs.count
      assert_equal "error", logs.first.severity
      assert_equal "Ivs::DisconnectPublisherConnectionService::RetryExhausted", logs.first.exception_class
      assert_equal @publisher.id, logs.first.actor_user_id
      assert_equal @store.id, logs.first.store_id
      refute_includes logs.first.attributes.to_json, "test-token"
    end
  end

  test "旧方式で4回以上の未解決行はAPIを呼ばず最終失敗にする" do
    with_publisher_client do
      issued = issue_token
      connection = StreamPublisherConnection.find_by!(request_id: issued[:request_id])
      connection.update!(disconnect_requested_at: Time.current, disconnect_reason: "end", disconnect_attempts: 10,
        last_disconnect_error: "Aws::IVSRealTime::Errors::AccessDeniedException", next_disconnect_retry_at: 30.minutes.from_now)
      DisconnectPublisherConnectionJob.perform_now(connection.id)
      assert_equal "failed", connection.reload.disconnect_state
      assert_equal 10, connection.disconnect_attempts
      assert_empty disconnect_requests
    end
  end

  test "外側transactionを取消した場合はAWS切断も試行回数も発生しない" do
    with_publisher_client do
      issued = issue_token
      StreamSession.transaction(requires_new: true) do
        cancel_token(issued)
        assert_empty disconnect_requests
        raise ActiveRecord::Rollback
      end
      connection = StreamPublisherConnection.find_by!(request_id: issued[:request_id])
      assert_nil connection.disconnect_requested_at
      assert_equal 0, connection.disconnect_attempts
      assert_empty disconnect_requests
    end
  end

  test "取消の切断が最終失敗でも本人の終了と履歴保存を妨げない" do
    with_publisher_client do
      issued = issue_token
      stub_published_participant(issued)
      confirm_token(issued)
      reconnect = issue_token(generation: 1)
      @ivs_client.stub_responses(:disconnect_participant, "AccessDeniedException")
      cancel_token(reconnect)
      connection = StreamPublisherConnection.find_by!(request_id: reconnect[:request_id])
      3.times do
        travel_to(connection.reload.next_disconnect_retry_at, with_usec: true) { DisconnectPublisherConnectionJob.perform_now(connection.id) }
      end
      ended = StreamSessions::EndService.new(stream_session: @stream_session, actor: @publisher, generation: 3).call
      assert ended.ended?
      assert_equal @publisher.id, ended.actual_publisher_user_id
      assert_equal "failed", StreamSessions::PublisherStateService.ended_payload(stream_session: ended)[:disconnect_state]
      assert_equal 4, connection.reload.disconnect_attempts
    end
  end

  test "AWSアカウントとリージョンで呼出間隔を共有し待機枠ではAWS試行を消費しない" do
    now = Time.current.change(usec: 0)
    travel_to(now, with_usec: true) do
      assert_nil Ivs::ReserveDisconnectSlotService.call(stage_arn: @booth.ivs_stage_arn)
      assert_equal now + 0.25, Ivs::ReserveDisconnectSlotService.call(stage_arn: @booth.ivs_stage_arn + "other")
      assert_nil Ivs::ReserveDisconnectSlotService.call(stage_arn: @booth.ivs_stage_arn.sub("123456789012", "000000000000"))
    end
    travel_to(now + 0.25, with_usec: true) do
      assert_nil Ivs::ReserveDisconnectSlotService.call(stage_arn: @booth.ivs_stage_arn)
    end
  end
end
