require "test_helper"
require_relative "../../support/consumption_test_support"

class DrinkOrders::ConsumeServiceTest < ActiveSupport::TestCase
  include ConsumptionTestSupport
  setup { build_consumption_fixture }

  test "H02 X準備 Y配信 Z担当で消化・通知・台帳をYへ一致させる" do
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      result = consume
      assert result.drink_order.consumed?
      assert_equal 100, result.store_ledger_entry.points
      assert_equal 0, @wallet.reload.reserved_points
      assert_equal 400, @wallet.available_points
      comment = Comment.find_by!(drink_order: @order)
      assert_equal @publisher.id, comment.user_id
      assert_equal @creator.id, @session.reload.started_by_cast_user_id
      assert_equal Comment::KIND_DRINK_CONSUMED, comment.kind
      assert_equal false, comment.metadata["publisher_unknown"]
      assert_equal @order.reload.consumed_at, result.store_ledger_entry.occurred_at
      assert_equal 1, WalletTransaction.where(ref: @order, kind: :consume).count
    end
  end

  test "H02 作成者・担当者・無所属・管理者も本人以外は金銭とコメントを変更しない" do
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      before = financial_snapshot
      [ @creator, @assigned, @outsider, @admin, @system, @customer, nil ].each do |actor|
        assert_raises(DrinkOrders::ConsumeService::ForbiddenError) { consume(actor: actor) }
        assert_equal before, financial_snapshot
      end
    end
  end

  test "H02 キャストとシステム管理者もその配信の本人なら消化できる" do
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      [ @assigned, @system ].each do |actor|
        @session.update!(actual_publisher_user: actor)
        order = @order.pending? ? @order : add_pending_drink
        consume(order: order, actor: actor)
        @order.reload
        assert_equal actor.id, Comment.find_by!(drink_order: order).user_id
      end
    end
  end

  test "H02 離席中の本人にも消化を許可する" do
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      @booth.update!(status: :away)
      assert consume.drink_order.consumed?
    end
  end

  test "H04 人物不明の配信や未開始準備は消化できない" do
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      @session.update!(actual_publisher_user: nil, actual_publisher_source: nil, actual_publisher_recorded_at: nil)
      before = financial_snapshot
      assert_raises(DrinkOrders::ConsumeService::ForbiddenError) { consume }
      assert_equal before, financial_snapshot
      @booth.update!(status: :standby)
      @session.update!(broadcast_started_at: nil)
      assert_raises(DrinkOrders::ConsumeService::ForbiddenError) { consume }
      assert_equal before, financial_snapshot
    end
  end

  test "H02 終了済み・現在参照なし・閉鎖・standbyは本人でも消化しない" do
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      [ { status: :offline }, { status: :standby }, { current_stream_session_id: nil }, { archived_at: Time.current } ].each do |change|
        @booth.update!(change)
        before = financial_snapshot
        assert_raises(DrinkOrders::ConsumeService::SessionEndedError) { consume }
        assert_equal before, financial_snapshot
        @booth.update!(status: :live, current_stream_session: @session, archived_at: nil)
      end
      @session.update!(status: :ended, ended_at: Time.current)
      assert_raises(DrinkOrders::ConsumeService::SessionEndedError) { consume }
    end
  end

  test "H02 退会済みの古い認証インスタンスと所属解除後の本人を拒否する" do
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      stale = User.find(@publisher.id)
      @publisher.update!(deleted_at: Time.current)
      assert_raises(DrinkOrders::ConsumeService::ForbiddenError) { consume(actor: stale) }
      @publisher.update!(deleted_at: nil)
      StoreMembership.where(store: @store, user: @publisher).delete_all
      assert_raises(DrinkOrders::ConsumeService::ForbiddenError) { consume }
    end
  end

  test "H02 FIFO・重複消化拒否・返却分除外とhold時点の金額を維持する" do
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      second = add_pending_drink(points: 70)
      assert_raises(DrinkOrders::ConsumeService::NotHeadError) { consume(order: second) }
      @item.update!(price_points: 500)
      assert_equal 100, consume.store_ledger_entry.points
      before = financial_snapshot
      assert_raises(DrinkOrders::ConsumeService::InvalidStatusError) { consume }
      assert_equal before, financial_snapshot
      DrinkOrder.transaction { DrinkOrders::RefundService.new(stream_session: @session).call! }
      assert second.reload.refunded?
      assert_equal 70, WalletTransaction.find_by!(ref: second, kind: :release).points
      assert_equal 100, StoreLedgerEntry.where(stream_session: @session).sum(:points)
      assert_equal 0, @wallet.reload.reserved_points
      assert_raises(DrinkOrders::ConsumeService::InvalidStatusError) { consume(order: second) }
    end
  end

  test "H02 通知保存の失敗は消化・財布・台帳を一緒に戻す" do
    original = DrinkOrders::ConsumptionCommentService.instance_method(:call!)
    DrinkOrders::ConsumptionCommentService.define_method(:call!) { raise ActiveRecord::RecordInvalid }
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      before = financial_snapshot
      assert_raises(ActiveRecord::RecordInvalid) { consume }
      assert_equal before, financial_snapshot
    end
  ensure
    DrinkOrders::ConsumptionCommentService.define_method(:call!, original)
  end

  test "H02 共通有効化前の既存消化は準備作成者通知の経路を保つ" do
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "false") do
      assert consume.drink_order.consumed?
      assert_nil @session.comments.sole.drink_order_id
      assert_equal @creator.id, @session.comments.sole.user_id
    end
  end
end
