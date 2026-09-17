require "test_helper"
require_relative "../../support/publisher_connection_test_support"

class Ivs::PublisherDisconnectRunnerTest < ActiveSupport::TestCase
  include PublisherConnectionTestSupport
  setup { build_publisher_fixture }

  test "運用runnerは既定で表示だけを行い一致する環境と対象を明示した場合だけ切断する" do
    with_publisher_client do
      issued = issue_token
      connection = StreamPublisherConnection.find_by!(request_id: issued[:request_id])
      connection.update!(disconnect_requested_at: Time.current, disconnect_reason: "cancel",
        disconnect_attempts: 4, disconnect_failed_at: Time.current)
      output, = run_script("--connection-id", connection.id.to_s)
      assert_equal false, JSON.parse(output)["applied"]
      assert_empty disconnect_requests
      args = [ "--connection-id", connection.id.to_s, "--apply", "--environment", Rails.env.to_s,
        "--database", ApplicationRecord.connection_db_config.database, "--request-id", connection.request_id,
        "--participant-id", connection.ivs_participant_id, "--stage-arn", connection.ivs_stage_arn ]
      output, = run_script(*args)
      assert_equal "disconnected", JSON.parse(output)["state"]
      assert_equal 5, connection.reload.disconnect_attempts
      assert_equal [ issued[:participant_id] ], disconnect_requests.pluck(:participant_id)
      refute @stream_session.reload.ended?
    end
  end

  test "環境 DBまたは保存済み参加者の指定が違う場合はAWSを呼ばない" do
    with_publisher_client do
      issued = issue_token
      connection = StreamPublisherConnection.find_by!(request_id: issued[:request_id])
      capture_io do
        error = assert_raises(SystemExit) do
          run_script("--connection-id", connection.id.to_s, "--apply", "--environment", "not-test",
            "--database", ApplicationRecord.connection_db_config.database, "--request-id", connection.request_id,
            "--participant-id", connection.ivs_participant_id, "--stage-arn", connection.ivs_stage_arn)
        end
        assert_equal 1, error.status
      end
      assert_empty disconnect_requests
      assert_equal 0, connection.reload.disconnect_attempts
    end
  end

  private

  def run_script(*args)
    before = ARGV.dup
    ARGV.replace(args)
    capture_io { load Rails.root.join("script/recover_publisher_disconnect.rb") }
  ensure
    ARGV.replace(before)
  end
end
