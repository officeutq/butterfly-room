require "test_helper"
require "timeout"
require_relative "../../support/consumption_test_support"

class DrinkOrders::ConsumptionConcurrencyTest < ActiveSupport::TestCase
  include ConsumptionTestSupport
  include ActiveJob::TestHelper
  self.use_transactional_tests = false

  setup { build_consumption_fixture }
  teardown { cleanup_consumption_fixture }

  test "H02 消化が終了より先なら消化分だけ売上とし残りを返却する" do
    second = add_pending_drink(points: 70)
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      first, last = run_race(:consume, :end)
      assert first.drink_order.consumed?
      assert last.ended?
      assert @order.reload.consumed?
      assert second.reload.refunded?
      assert_equal 100, StoreLedgerEntry.where(stream_session: @session).sum(:points)
      assert_equal 70, WalletTransaction.where(ref: second, kind: :release).sum(:points)
      assert_equal 1, @session.comments.count
    end
  end

  test "H02 終了が消化より先なら注文を返却し待機した消化要求を拒否する" do
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      first, last = run_race(:end, :consume)
      assert first.ended?
      assert_instance_of DrinkOrders::ConsumeService::SessionEndedError, last
      assert @order.reload.refunded?
      assert_empty StoreLedgerEntry.where(stream_session: @session)
      assert_empty @session.comments
      assert_equal 100, WalletTransaction.where(ref: @order, kind: :release).sum(:points)
    end
  end

  test "H02 同時に同じ注文を消化しても金銭確定とコメントは一回だけ" do
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      first, last = run_race(:consume, :consume)
      assert first.drink_order.consumed?
      assert_instance_of DrinkOrders::ConsumeService::InvalidStatusError, last
      assert_equal 1, StoreLedgerEntry.where(stream_session: @session).count
      assert_equal 1, WalletTransaction.where(ref: @order, kind: :consume).count
      assert_equal 1, @session.comments.count
      assert_equal 0, @wallet.reload.reserved_points
    end
  end

  test "H02 最外側commit後だけ通知しrollbackで通知を残さない" do
    sent = []
    original = NotifyDrinkConsumptionJob.method(:perform_now)
    NotifyDrinkConsumptionJob.define_singleton_method(:perform_now) do |id|
      sent << [ id, ActiveRecord::Base.connection.transaction_open? ]
    end
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      DrinkOrder.transaction do
        consume
        assert_empty sent
        raise ActiveRecord::Rollback
      end
      assert_empty sent
      assert @order.reload.pending?
      assert_empty @session.comments
      DrinkOrder.transaction do
        consume
        assert_empty sent
      end
      assert_equal [ [ @session.comments.sole.id, false ] ], sent
    end
  ensure
    NotifyDrinkConsumptionJob.define_singleton_method(:perform_now, original)
  end

  test "H02 通知失敗のジョブ再試行は同じコメントだけを送り消化結果を保持する" do
    original = CommentNotifier.method(:append)
    CommentNotifier.define_singleton_method(:append) { |_comment| raise IOError, "notification unavailable" }
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      assert_enqueued_jobs 1, only: NotifyDrinkConsumptionJob do
        assert consume.drink_order.consumed?
      end
      comment = @session.comments.sole
      assert_equal [ comment.id ], enqueued_jobs.last[:args]
      before = financial_snapshot
      delivered = []
      CommentNotifier.define_singleton_method(:append) { |record| delivered << record.id }
      2.times { NotifyDrinkConsumptionJob.perform_now(comment.id) }
      assert_equal [ comment.id, comment.id ], delivered
      assert_equal before, financial_snapshot
    end
  ensure
    CommentNotifier.define_singleton_method(:append, original)
  end

  test "H02 通知キューまで失敗しても確定した消化を失敗応答にしない" do
    original = NotifyDrinkConsumptionJob.method(:perform_now)
    NotifyDrinkConsumptionJob.define_singleton_method(:perform_now) { |_id| raise IOError, "queue unavailable" }
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      assert consume.drink_order.consumed?
      assert_equal 1, @session.comments.count
      assert_equal 100, StoreLedgerEntry.where(stream_session: @session).sum(:points)
      assert_equal 0, @wallet.reload.reserved_points
    end
  ensure
    NotifyDrinkConsumptionJob.define_singleton_method(:perform_now, original)
  end

  private

  def run_race(first_operation, second_operation)
    locked = Queue.new
    proceed = Queue.new
    waiting = Queue.new
    threads = []
    threads << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Booth.find(@booth.id).with_lock do
          result = operation(first_operation)
          locked << true
          Timeout.timeout(20) { proceed.pop }
          result
        end
      end
    end
    Timeout.timeout(10) { locked.pop }
    threads << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        waiting << connection.select_value("SELECT pg_backend_pid()")
        operation(second_operation)
      rescue DrinkOrders::ConsumeService::InvalidStatusError, DrinkOrders::ConsumeService::SessionEndedError => error
        error
      end
    end
    pid = Timeout.timeout(10) { waiting.pop }
    ActiveRecord::Base.uncached do
      Timeout.timeout(10) do
        loop do
          break if ActiveRecord::Base.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}") == "Lock"
          sleep 0.01
        end
      end
    end
    proceed << true
    threads.map { |thread| Timeout.timeout(10) { thread.value } }
  ensure
    proceed << true
    threads.each { |thread| thread.join(10) || thread.kill }
  end

  def operation(kind)
    actor = User.find(@publisher.id)
    if kind == :consume
      consume(actor: actor)
    else
      StreamSessions::EndService.new(stream_session: StreamSession.find(@session.id), actor: actor, generation: 0).call
    end
  end
end
