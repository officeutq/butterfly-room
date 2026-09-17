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

  test "重複した切断ジョブは別DB接続でも同じ参加者を一度だけ切断する" do
    entered = Queue.new
    proceed = Queue.new
    threads = []
    with_publisher_client do
      issued = issue_token
      connection = StreamPublisherConnection.find_by!(request_id: issued[:request_id])
      connection.update!(disconnect_requested_at: Time.current, disconnect_reason: "cancel")
      original = @ivs_client.method(:disconnect_participant)
      @ivs_client.define_singleton_method(:disconnect_participant) do |**arguments|
        entered << true
        Timeout.timeout(10) { proceed.pop }
        original.call(**arguments)
      end
      2.times do |index|
        threads << Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            Ivs::DisconnectPublisherConnectionService.new(connection_id: connection.id).call
          end
        end
        Timeout.timeout(10) { entered.pop } if index.zero?
      end
      proceed << true
      threads.each { |thread| Timeout.timeout(10) { thread.value } }
      assert_equal 1, connection.reload.disconnect_attempts
      assert connection.released_at
      assert_equal [ issued[:participant_id] ], disconnect_requests.pluck(:participant_id)
    end
  ensure
    proceed << true
    threads.each { |thread| thread.join(10) || thread.kill }
  end

  test "配信開始要求が先なら非公開化は発行完了を待ち開始中として拒否する" do
    entered = Queue.new
    proceed = Queue.new
    waiting = Queue.new
    threads = []
    original = @ivs_client.method(:create_participant_token)
    @ivs_client.define_singleton_method(:create_participant_token) do |**arguments|
      response = original.call(**arguments)
      entered << true
      Timeout.timeout(30) { proceed.pop }
      response
    end
    with_publisher_client do
      threads << claim_in_thread(@stream_session.id, @publisher.id)
      Timeout.timeout(10) { entered.pop }
      threads << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          waiting << connection.select_value("SELECT pg_backend_pid()")
          Stores::UpdateService.new(store: Store.find(@store.id), attributes: { published: false }).call
        rescue Stores::UpdateService::UnpublishBlocked
          :blocked
        end
      end
      wait_for_database_lock(Timeout.timeout(10) { waiting.pop })
      proceed << true
      issued, publication = threads.map { |thread| Timeout.timeout(10) { thread.value } }
      assert_equal "issued", issued[:state]
      assert_equal :blocked, publication
      assert @store.reload.published?
      assert_equal 1, StreamPublisherConnection.unreleased.where(booth: @booth).count
    end
  ensure
    proceed << true
    threads.each { |thread| thread.join(10) || thread.kill }
    @ivs_client.define_singleton_method(:create_participant_token, original)
  end

  test "非公開化が先なら配信開始要求は保存完了を待ちトークンを発行せず拒否する" do
    entered = Queue.new
    proceed = Queue.new
    waiting = Queue.new
    threads = []
    with_publisher_client do
      threads << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Stores::UpdateService.new(store: Store.find(@store.id), attributes: { published: false }).call do
            entered << true
            Timeout.timeout(30) { proceed.pop }
          end
        end
      end
      Timeout.timeout(10) { entered.pop }
      threads << claim_in_thread(@stream_session.id, @publisher.id, pid_queue: waiting)
      wait_for_database_lock(Timeout.timeout(10) { waiting.pop })
      proceed << true
      publication, issued = threads.map { |thread| Timeout.timeout(10) { thread.value } }
      refute publication.published?
      assert_equal "store_unpublished", issued[:error]
      refute @store.reload.published?
      assert_empty @ivs_client.api_requests
      assert_empty StreamPublisherConnection.where(booth: @booth)
    end
  ensure
    proceed << true
    threads.each { |thread| thread.join(10) || thread.kill }
  end

  test "H01 表示通知が失敗しても開始成功とYを保持し再確認が同じ結果を返す" do
    original = StreamSessionNotifier.method(:broadcast_stream_state)
    StreamSessionNotifier.define_singleton_method(:broadcast_stream_state) { |booth:| raise IOError, "display unavailable" }
    with_publisher_client do
      issued = issue_token
      stub_published_participant(issued)
      assert_equal "confirmed", confirm_token(issued)[:state]
      recorded = @stream_session.reload.attributes
      assert_equal @publisher.id, @stream_session.actual_publisher_user_id
      assert @booth.reload.live?
      assert_equal "confirmed", confirm_token(issued)[:state]
      assert_equal recorded, @stream_session.reload.attributes
    end
  ensure
    StreamSessionNotifier.define_singleton_method(:broadcast_stream_state, original)
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

  test "E04 配信成功を先に確定しても退会は待機後に本人配信を終了する" do
    verify_withdrawal_race(first: :confirm)
  end

  test "E04 退会の取消が先なら待機中の開始確定を拒否し準備を残す" do
    verify_withdrawal_race(first: :withdraw)
  end

  test "E04 新規トークン発行と退会は外部キーの待ちでデッドロックせず接続を取り消す" do
    entered = Queue.new
    proceed = Queue.new
    waiting = Queue.new
    threads = []
    original = @ivs_client.method(:create_participant_token)
    @ivs_client.define_singleton_method(:create_participant_token) do |**arguments|
      result = original.call(**arguments)
      entered << true
      Timeout.timeout(30) { proceed.pop }
      result
    end
    with_publisher_client do
      threads << claim_in_thread(@stream_session.id, @publisher.id)
      Timeout.timeout(10) { entered.pop }
      threads << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          waiting << connection.select_value("SELECT pg_backend_pid()")
          Accounts::WithdrawalService.new(user: User.find(@publisher.id)).call!
        end
      end
      wait_for_database_lock(Timeout.timeout(10) { waiting.pop })
      proceed << true
      issued, result = threads.map { |thread| Timeout.timeout(10) { thread.value } }
      assert_equal "issued", issued[:state]
      assert result.user.deleted?
      assert @booth.reload.standby?
      assert_nil @stream_session.reload.current_publisher_connection_id
      assert_equal [ issued[:participant_id] ], disconnect_requests.pluck(:participant_id)
    end
  ensure
    proceed << true
    threads.each { |thread| thread.join(10) || thread.kill }
    @ivs_client.define_singleton_method(:create_participant_token, original)
  end

  test "E05 通知とジョブは外側commit後のみでrollbackや重複終了では増えない" do
    notifications = []
    ended_method = StreamSessionNotifier.method(:broadcast_ended)
    state_method = StreamSessionNotifier.method(:broadcast_stream_state)
    StreamSessionNotifier.define_singleton_method(:broadcast_ended) { |session, forced:| notifications << [ :ended, session.id, forced ] }
    StreamSessionNotifier.define_singleton_method(:broadcast_stream_state) { |booth:| notifications << [ :state, booth.id ] }
    jobs = []
    enqueue_method = Ivs::DisconnectPublisherConnectionService.method(:enqueue)
    Ivs::DisconnectPublisherConnectionService.define_singleton_method(:enqueue) { |id, **_options| jobs << id }
    with_publisher_client do
      issued = issue_token
      stub_published_participant(issued)
      confirm_token(issued)
      notifications.clear
      StreamSessionNotifier.define_singleton_method(:broadcast_stream_state) do |booth:|
        notifications << [ :state, booth.id ]
        raise IOError, "notification unavailable"
      end
      @ivs_client.stub_responses(:disconnect_participant, "AccessDeniedException")
      end_operation = -> {
        StreamSessions::EndService.new(stream_session: StreamSession.find(@stream_session.id), actor: @publisher,
          request_id: issued[:request_id], generation: 1).call
      }
      ActiveRecord::Base.transaction do
        end_operation.call
        assert_empty notifications
        assert_empty jobs
        raise ActiveRecord::Rollback
      end
      assert_empty notifications
      assert_empty jobs
      refute @stream_session.reload.ended?
      ActiveRecord::Base.transaction do
        end_operation.call
        assert_empty notifications
        assert_empty jobs
      end
      assert_equal 1, notifications.count { |n| n.first == :ended }
      assert_equal 1, notifications.count { |n| n.first == :state }
      assert_equal [ @stream_session.reload.current_publisher_connection_id ], jobs
      end_operation.call
      assert_equal 2, notifications.size
      assert_equal 1, jobs.size
      notifications.clear
      jobs.clear
      connection = @stream_session.current_publisher_connection
      connection.update!(next_disconnect_retry_at: Time.current)
      RetryPendingPublisherDisconnectsJob.perform_now
      assert_includes jobs, connection.id
      assert_empty notifications
    end
  ensure
    StreamSessionNotifier.define_singleton_method(:broadcast_ended, ended_method)
    StreamSessionNotifier.define_singleton_method(:broadcast_stream_state, state_method)
    Ivs::DisconnectPublisherConnectionService.define_singleton_method(:enqueue, enqueue_method)
  end

  test "E03 閉鎖が先なら待機していた開始確定はブースを再開しない" do
    entered = Queue.new
    proceed = Queue.new
    waiting = Queue.new
    threads = []
    original = @ivs_client.method(:disconnect_participant)
    @ivs_client.define_singleton_method(:disconnect_participant) do |**arguments|
      result = original.call(**arguments)
      entered << true
      Timeout.timeout(30) { proceed.pop }
      result
    end
    with_publisher_client do
      issued = issue_token
      stub_published_participant(issued)
      threads << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Booths::ArchiveService.new(booth: Booth.find(@booth.id), actor: @publisher,
            stream_session_id: @stream_session.id.to_s, generation: 1).call!
        end
      end
      Timeout.timeout(10) { entered.pop }
      threads << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          waiting << connection.select_value("SELECT pg_backend_pid()")
          StreamSessions::ConfirmPublisherService.new(stream_session: StreamSession.find(@stream_session.id), actor: @publisher,
            request_id: issued[:request_id], generation: 1).call
        rescue StreamSessions::PublisherControl::Error => error
          { error: error.code }
        end
      end
      wait_for_database_lock(Timeout.timeout(10) { waiting.pop })
      proceed << true
      closed, rejected = threads.map { |thread| Timeout.timeout(10) { thread.value } }
      assert closed.archived?
      assert_equal "stale_publisher_request", rejected[:error]
      assert @stream_session.reload.ended?
      assert_nil @stream_session.actual_publisher_user_id
      assert @booth.reload.offline?
    end
  ensure
    proceed << true
    threads.each { |thread| thread.join(10) || thread.kill }
    @ivs_client.define_singleton_method(:disconnect_participant, original)
  end

  private

  def verify_withdrawal_race(first:)
    entered = Queue.new
    proceed = Queue.new
    waiting = Queue.new
    threads = []
    operation = first == :confirm ? :get_participant : :disconnect_participant
    original = @ivs_client.method(operation)
    @ivs_client.define_singleton_method(operation) do |**arguments|
      result = original.call(**arguments)
      entered << true
      Timeout.timeout(30) { proceed.pop }
      result
    end
    with_publisher_client do
      issued = issue_token
      stub_published_participant(issued)
      run = lambda do |action, pid_queue|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            actor = User.find(@publisher.id)
            pid_queue << connection.select_value("SELECT pg_backend_pid()") if pid_queue
            if action == :withdraw
              Accounts::WithdrawalService.new(user: actor).call!
            else
              StreamSessions::ConfirmPublisherService.new(stream_session: StreamSession.find(@stream_session.id),
                actor: actor, request_id: issued[:request_id], generation: 1).call
            end
          rescue StreamSessions::PublisherControl::Error => error
            { error: error.code }
          end
        end
      end
      threads << run.call(first, nil)
      Timeout.timeout(10) { entered.pop }
      threads << run.call(first == :confirm ? :withdraw : :confirm, waiting)
      pid = Timeout.timeout(10) { waiting.pop }
      if first == :confirm
        wait_for_database_lock(pid)
      else
        # 取消のDB確定後にAWS切断するので、確認要求は退会済みを即座に拒否する。
        assert_equal "forbidden", Timeout.timeout(10) { threads.last.value }[:error]
      end
      proceed << true
      results = threads.map { |thread| Timeout.timeout(10) { thread.value } }
      assert @publisher.reload.deleted?
      assert @store.reload.published?
      refute @booth.reload.archived?
      if first == :confirm
        assert_equal "confirmed", results.first[:state]
        assert @stream_session.reload.ended?
        assert_equal @publisher.id, @stream_session.actual_publisher_user_id
        assert @booth.offline?
      else
        assert_equal "forbidden", results.last[:error]
        refute @stream_session.reload.ended?
        assert_nil @stream_session.actual_publisher_user_id
        assert @booth.standby?
      end
      assert_equal [ issued[:participant_id] ], disconnect_requests.pluck(:participant_id)
    end
  ensure
    proceed << true
    threads.each { |thread| thread.join(10) || thread.kill }
    @ivs_client.define_singleton_method(operation, original)
  end

  def wait_for_database_lock(pid)
    ActiveRecord::Base.uncached do
      Timeout.timeout(10) do
        loop do
          break if ActiveRecord::Base.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}") == "Lock"
          sleep 0.01
        end
      end
    end
  end

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
