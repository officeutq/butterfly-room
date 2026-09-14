require "test_helper"
require "timeout"
require_relative "../../support/publisher_connection_test_support"

class StreamSessions::PublisherConnectionConcurrencyTest < ActiveSupport::TestCase
  include PublisherConnectionTestSupport
  self.use_transactional_tests = false

  setup { build_publisher_fixture }

  teardown do
    # 別DB接続の検証でコミットした、このテスト専用データだけを片付ける。
    booth_ids = Booth.where(store_id: @store.id).pluck(:id)
    session_ids = StreamSession.where(store_id: @store.id).pluck(:id)
    Booth.where(id: booth_ids).update_all(current_stream_session_id: nil)
    StreamSession.where(id: session_ids).update_all(current_publisher_connection_id: nil)
    StreamPublisherConnection.where(stream_session_id: session_ids).delete_all
    StreamSession.where(id: session_ids).delete_all
    BoothCast.where(booth_id: booth_ids).delete_all
    Booth.where(id: booth_ids).delete_all
    StoreMembership.where(store_id: @store.id).delete_all
    User.where(id: [ @creator.id, @publisher.id, @other_publisher.id ]).delete_all
    Store.where(id: @store.id).delete_all
  end

  test "S02 同じ準備へ二人が同時開始しても勝者だけがトークンを受け取る" do
    verify_concurrent_claims(second_session: @stream_session, second_actor: @other_publisher)
  end

  test "S02 同じ人が二ブースを同時開始しても部分一意索引で一件に絞る" do
    second_booth = build_prepared_booth("concurrent-other-#{SecureRandom.hex(6)}")
    verify_concurrent_claims(second_session: second_booth.current_stream_session, second_actor: @publisher)
  end

  test "R03 配信成功が先に確定すると待機していた取消は成功実績を消さない" do
    verify_confirmation_race(first: :confirm)
  end

  test "R03 取消が先に確定すると待機していた成功通知は実績を作らない" do
    verify_confirmation_race(first: :cancel)
  end

  test "R02 二端末から同じ世代で復帰しても新接続を一件だけ発行する" do
    entered = Queue.new
    continue_first = Queue.new
    second_pid = Queue.new
    threads = []
    original = @ivs_client.method(:disconnect_participant)
    with_publisher_client do
      first = issue_token
      stub_published_participant(first)
      confirm_token(first)
      started_at = @stream_session.reload.broadcast_started_at
      @ivs_client.define_singleton_method(:disconnect_participant) do |**arguments|
        response = original.call(**arguments)
        entered << ActiveRecord::Base.connection.select_value("SELECT pg_backend_pid()")
        Timeout.timeout(30) { continue_first.pop }
        response
      end
      threads << claim_in_thread(@stream_session.id, @publisher.id, generation: 1)
      first_pid = Timeout.timeout(10) { entered.pop }
      threads << claim_in_thread(@stream_session.id, @publisher.id, generation: 1, pid_queue: second_pid)
      pid = Timeout.timeout(10) { second_pid.pop }
      refute_equal first_pid, pid
      ActiveRecord::Base.uncached do
        Timeout.timeout(10) do
          loop do
            break if ActiveRecord::Base.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}") == "Lock"
            sleep 0.01
          end
        end
      end
      continue_first << true
      winner, loser = threads.map { |thread| Timeout.timeout(10) { thread.value } }
      assert_equal "issued", winner[:state]
      assert_equal "stale_publisher_request", loser[:error]
      assert_equal 2, issued_count
      assert_equal 1, disconnect_requests.size
      assert_equal 1, StreamPublisherConnection.unreleased.where(user: @publisher).count
      assert_equal winner[:request_id], @stream_session.reload.current_publisher_connection.request_id
      assert_equal @publisher.id, @stream_session.actual_publisher_user_id
      assert_equal started_at, @stream_session.broadcast_started_at
    end
  ensure
    continue_first << true
    threads.each { |thread| thread.join(10) || thread.kill }
    @ivs_client.define_singleton_method(:disconnect_participant, original)
  end

  private

  def verify_confirmation_race(first:)
    entered = Queue.new
    continue_first = Queue.new
    second_pid = Queue.new
    threads = []
    operation = first == :confirm ? :get_participant : :disconnect_participant
    original = @ivs_client.method(operation)
    @ivs_client.define_singleton_method(operation) do |**arguments|
      response = original.call(**arguments)
      entered << ActiveRecord::Base.connection.select_value("SELECT pg_backend_pid()")
      Timeout.timeout(30) { continue_first.pop }
      response
    end
    with_publisher_client do
      issued = issue_token
      stub_published_participant(issued)
      run = lambda do |action, pid_queue|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            pid_queue << connection.select_value("SELECT pg_backend_pid()") if pid_queue
            service = action == :confirm ? StreamSessions::ConfirmPublisherService : StreamSessions::CancelPublisherConnectionService
            service.new(stream_session: StreamSession.find(@stream_session.id), actor: User.find(@publisher.id),
              request_id: issued[:request_id], generation: issued[:generation]).call
          rescue StreamSessions::PublisherControl::Error => error
            { error: error.code }
          end
        end
      end
      threads << run.call(first, nil)
      first_pid = Timeout.timeout(10) { entered.pop }
      threads << run.call(first == :confirm ? :cancel : :confirm, second_pid)
      pid = Timeout.timeout(10) { second_pid.pop }
      refute_equal first_pid, pid
      ActiveRecord::Base.uncached do
        Timeout.timeout(10) do
          loop do
            break if ActiveRecord::Base.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}") == "Lock"
            sleep 0.01
          end
        end
      end
      continue_first << true
      results = threads.map { |thread| Timeout.timeout(10) { thread.value } }
      if first == :confirm
        assert_equal [ "confirmed", "confirmed" ], results.map { |result| result[:state] }
        assert_equal @publisher.id, @stream_session.reload.actual_publisher_user_id
        assert @booth.reload.live?
        assert_empty disconnect_requests
      else
        assert_equal "cancelled", results.first[:state]
        assert_equal "stale_publisher_request", results.last[:error]
        assert_nil @stream_session.reload.actual_publisher_user_id
        assert_nil @stream_session.broadcast_started_at
        assert @booth.reload.standby?
        assert_equal 1, disconnect_requests.size
      end
    end
  ensure
    continue_first << true
    threads.each { |thread| thread.join(10) || thread.kill }
    @ivs_client.define_singleton_method(operation, original)
  end

  def verify_concurrent_claims(second_session:, second_actor:)
    first_mint_entered = Queue.new
    continue_first_mint = Queue.new
    second_pid = Queue.new
    threads = []
    sequence = 0
    sequence_lock = Mutex.new
    original_mint = @ivs_client.method(:create_participant_token)
    # 発行応答を受け取り、DBの保存がまだ確定していない位置で先行要求を止める。
    @ivs_client.define_singleton_method(:create_participant_token) do |**arguments|
      number = sequence_lock.synchronize { sequence += 1 }
      response = original_mint.call(**arguments)
      if number == 1
        first_mint_entered << ActiveRecord::Base.connection.select_value("SELECT pg_backend_pid()")
        Timeout.timeout(30) { continue_first_mint.pop }
      end
      response
    end

    with_publisher_client do
      threads << claim_in_thread(@stream_session.id, @publisher.id)
      first_pid = Timeout.timeout(10) { first_mint_entered.pop }
      threads << claim_in_thread(second_session.id, second_actor.id, pid_queue: second_pid)
      pid = Timeout.timeout(10) { second_pid.pop }
      refute_equal first_pid, pid
      ActiveRecord::Base.uncached do
        Timeout.timeout(10) do
          loop do
            waiting = ActiveRecord::Base.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}")
            break if waiting == "Lock"
            sleep 0.01
          end
        end
      end
      continue_first_mint << true
      first, second = threads.map { |thread| Timeout.timeout(10) { thread.value } }

      assert_equal "issued", first[:state]
      assert_includes %w[stale_publisher_request publisher_in_use], second[:error]
      assert_equal 1, issued_count
      assert_equal 1, StreamPublisherConnection.unreleased.where(booth_id: [ @booth.id, second_session.booth_id ]).count
      assert_empty disconnect_requests
      assert_nil @stream_session.reload.actual_publisher_user
      assert_nil second_session.reload.actual_publisher_user

      assert_equal "cancelled", cancel_token(first)[:state]
      retry_result = issue_token(actor: second_actor, stream_session: second_session.reload,
        generation: second_session.publisher_generation)
      assert_equal "issued", retry_result[:state]
      assert_equal second_actor.id, second_session.reload.current_publisher_connection.user_id
    end
  ensure
    continue_first_mint << true
    threads.each { |thread| thread.join(10) || thread.kill }
    @ivs_client.define_singleton_method(:create_participant_token, original_mint)
  end

  def claim_in_thread(session_id, actor_id, pid_queue: nil, generation: 0)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        pid_queue << connection.select_value("SELECT pg_backend_pid()") if pid_queue
        issue_token(stream_session: StreamSession.find(session_id), actor: User.find(actor_id), generation: generation)
      rescue StreamSessions::PublisherControl::Error => error
        { error: error.code }
      end
    end
  end
end
