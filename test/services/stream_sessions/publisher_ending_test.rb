require "test_helper"
require_relative "../../support/publisher_connection_test_support"

class StreamSessions::PublisherEndingTest < ActiveSupport::TestCase
  include PublisherConnectionTestSupport

  setup { build_publisher_fixture }

  test "E01 世代0の旧準備を作成者以外の権限者が終了できる" do
    with_publisher_client do
      result = finish(generation: 0)
      assert result.ended?
      assert_nil result.broadcast_started_at
      assert_nil result.actual_publisher_user_id
      assert_equal @creator.id, result.started_by_cast_user_id
      assert @booth.reload.offline?
      assert_nil @booth.current_stream_session_id
      assert_empty disconnect_requests
      assert_equal result.id, finish(generation: 0).id
    end
  end

  test "E02 本人の終了は返却一回だけで消化済み売上と本人の実績を保つ" do
    with_publisher_client do
      issued = begin_broadcast
      create_drinks
      history = @stream_session.reload.attributes.slice("actual_publisher_user_id", "broadcast_started_at", "started_by_cast_user_id")
      ledger = @ledger.attributes
      2.times { finish(**issued.slice(:request_id, :generation)) }
      assert @pending.reload.refunded?
      assert @consumed.reload.consumed?
      assert_equal 500, @wallet.reload.available_points
      assert_equal 0, @wallet.reserved_points
      assert_equal 1, WalletTransaction.release.where(ref: @pending).count
      assert_equal ledger, @ledger.reload.attributes
      assert_equal history, @stream_session.reload.attributes.slice(*history.keys)
      assert_equal [ issued[:participant_id] ], disconnect_requests.pluck(:participant_id)
    end
  end

  test "E02 通常終了は本人のみで管理終了は管理者のみ" do
    with_publisher_client do
      issued = begin_broadcast
      [ @creator, @other_publisher ].each do |actor|
        assert_error("forbidden") { finish(actor: actor, **issued.slice(:request_id, :generation)) }
      end
      assert_error("forbidden") { StreamSessions::ForceEndService.new(stream_session: @stream_session, actor: @creator, generation: 1).call }
      assert_empty disconnect_requests
      StreamSessions::ForceEndService.new(stream_session: @stream_session, actor: @other_publisher, generation: 1).call
      assert @stream_session.reload.ended?
      assert_equal @publisher.id, @stream_session.actual_publisher_user_id
    end
  end

  test "R03 古い終了は新接続を終了せず終了済みへの再送も後続セッションを変更しない" do
    with_publisher_client do
      first = begin_broadcast
      second = issue_token(generation: 1)
      stub_published_participant(second)
      confirm_token(second)
      assert_error("stale_publisher_request") { finish(**first.slice(:request_id, :generation)) }
      assert @booth.reload.live?
      finish(**second.slice(:request_id, :generation))
      new_session = StreamSession.create!(booth: @booth, store: @store, started_by_cast_user: @creator,
        started_at: Time.current, status: :live, ivs_stage_arn: @booth.ivs_stage_arn)
      @booth.update!(status: :standby, current_stream_session: new_session)
      finish(**second.slice(:request_id, :generation))
      assert_equal new_session.id, @booth.reload.current_stream_session_id
      refute new_session.reload.ended?
      assert_equal [ first[:participant_id], second[:participant_id] ], disconnect_requests.pluck(:participant_id)
    end
  end

  test "E05 切断失敗でも終了と返却を確定し後日のジョブは外部切断だけを行う" do
    with_publisher_client do
      issued = begin_broadcast
      create_drinks
      @ivs_client.stub_responses(:disconnect_participant, "AccessDeniedException")
      finish(**issued.slice(:request_id, :generation))
      assert @stream_session.reload.ended?
      assert @pending.reload.refunded?
      connection = @stream_session.current_publisher_connection
      assert_equal "end", connection.disconnect_reason
      assert_nil connection.released_at
      assert StreamSessions::PublisherStateService.ended_payload(stream_session: @stream_session)[:disconnect_pending]
      DisconnectPublisherConnectionJob.perform_now(connection.id)
      assert_equal 1, disconnect_requests.size
      travel_to(connection.next_disconnect_retry_at + 1.second) do
        @ivs_client.stub_responses(:disconnect_participant, {})
        DisconnectPublisherConnectionJob.perform_now(connection.id)
      end
      assert connection.reload.released_at
      assert_equal 1, WalletTransaction.release.where(ref: @pending).count
      assert_equal [ issued[:participant_id] ] * 2, disconnect_requests.pluck(:participant_id)
    end
  end

  test "E05 DB失敗は終了返却を戻しAWSを切断せず後続の終了で回復する" do
    with_publisher_client do
      issued = begin_broadcast
      create_drinks
      @hold.destroy!
      assert_raises(DrinkOrders::RefundService::MissingHold) { finish(**issued.slice(:request_id, :generation)) }
      refute @stream_session.reload.ended?
      assert @pending.reload.pending?
      assert @booth.reload.live?
      assert_nil @stream_session.current_publisher_connection.reload.disconnect_requested_at
      assert_empty disconnect_requests
      @hold = WalletTransaction.create!(wallet: @wallet, ref: @pending, kind: :hold, points: -100, occurred_at: Time.current)
      finish(**issued.slice(:request_id, :generation))
      assert @pending.reload.refunded?
      assert_equal [ issued[:participant_id] ], disconnect_requests.pluck(:participant_id)
    end
  end

  test "E03 準備の手動閉鎖と古い画面拒否は配信中の手動閉鎖と区別する" do
    with_publisher_client do
      assert_error("stale_publisher_request") { archive(session_id: "") }
      first = issue_token
      assert_error("stale_publisher_request") { archive }
      stub_published_participant(first)
      confirm_token(first)
      assert_error("not_joinable") { archive(generation: 1) }
      assert_empty disconnect_requests
      StreamSessions::ForceEndService.new(stream_session: @stream_session, actor: @publisher, generation: 1).call
      archive(session_id: "", generation: nil)
      assert @booth.reload.archived?
    end
  end

  test "E03 未配信の準備を正規終了して閉鎖し実績を作らない" do
    with_publisher_client do
      archive
      assert @booth.reload.archived?
      assert @stream_session.reload.ended?
      assert_nil @stream_session.broadcast_started_at
    end
  end

  test "E04 共同管理者の本人配信だけ終了返却し店舗とブースを残す" do
    with_publisher_client do
      issued = begin_broadcast
      @booth.update!(status: :away)
      create_drinks
      other_booth = build_prepared_booth("other-preparation")
      other_booth.current_stream_session.update!(started_by_cast_user: @publisher)
      Accounts::WithdrawalService.new(user: @publisher).call!
      assert @publisher.reload.deleted?
      assert @stream_session.reload.ended?
      assert @pending.reload.refunded?
      assert @store.reload.published?
      refute @booth.reload.archived?
      assert other_booth.reload.standby?
      assert_equal @publisher.id, other_booth.current_stream_session.started_by_cast_user_id
      assert_equal [ issued[:participant_id] ], disconnect_requests.pluck(:participant_id)
    end
  end

  test "E04 共同管理者の未確定開始だけ取り消し同じ準備を残す" do
    with_publisher_client do
      issued = issue_token
      title = @stream_session.title
      Accounts::WithdrawalService.new(user: @publisher).call!
      assert @publisher.reload.deleted?
      assert @booth.reload.standby?
      assert_equal @stream_session.id, @booth.current_stream_session_id
      refute @stream_session.reload.ended?
      assert_equal title, @stream_session.title
      assert_nil @stream_session.actual_publisher_user_id
      assert_nil @stream_session.current_publisher_connection_id
      assert_error("forbidden") { confirm_token(issued) }
      assert_equal "issued", issue_token(actor: @other_publisher, generation: 2)[:state]
    end
  end

  test "E04 他人の配信は準備作成者である管理者が退会しても継続する" do
    with_publisher_client do
      @stream_session.update!(started_by_cast_user: @other_publisher)
      begin_broadcast
      Accounts::WithdrawalService.new(user: @other_publisher).call!
      assert @other_publisher.reload.deleted?
      assert @booth.reload.live?
      refute @stream_session.reload.ended?
      assert_empty disconnect_requests
    end
  end

  test "E04 本人の再接続中は準備扱いに戻さず配信を終了する" do
    with_publisher_client do
      begin_broadcast
      second = issue_token(generation: 1)
      Accounts::WithdrawalService.new(user: @publisher).call!
      assert @stream_session.reload.ended?
      assert_equal @publisher.id, @stream_session.actual_publisher_user_id
      assert_equal second[:participant_id], disconnect_requests.last[:participant_id]
      refute @booth.reload.archived?
    end
  end

  test "E05 復帰取消の切断をジョブが完了した後は未再接続でも本人が終了できる" do
    with_publisher_client do
      begin_broadcast
      second = issue_token(generation: 1)
      @ivs_client.stub_responses(:disconnect_participant, "AccessDeniedException")
      cancel_token(second)
      connection = @stream_session.reload.current_publisher_connection
      @ivs_client.stub_responses(:disconnect_participant, {})
      travel_to(connection.next_disconnect_retry_at + 1.second) { DisconnectPublisherConnectionJob.perform_now(connection.id) }
      assert connection.reload.released_at
      finish(generation: 3)
      assert @stream_session.reload.ended?
      assert_equal @publisher.id, @stream_session.actual_publisher_user_id
    end
  end

  test "E04 キャストの開始途中の退会は準備終了と閉鎖と所属解除を行う" do
    with_publisher_client do
      StoreMembership.create!(store: @store, user: @creator, membership_role: :cast)
      issued = issue_token(actor: @creator)
      @ivs_client.stub_responses(:disconnect_participant, "AccessDeniedException")
      Accounts::WithdrawalService.new(user: @creator).call!
      assert @creator.reload.deleted?
      assert @booth.reload.archived?
      assert @stream_session.reload.ended?
      assert_nil @stream_session.actual_publisher_user_id
      assert_nil @stream_session.broadcast_started_at
      refute StoreMembership.exists?(store: @store, user: @creator)
      assert_equal issued[:participant_id], disconnect_requests.last[:participant_id]
      assert StreamPublisherConnection.disconnect_pending.where(user: @creator).exists?
      connection = @stream_session.current_publisher_connection
      @ivs_client.stub_responses(:disconnect_participant, {})
      travel_to(connection.next_disconnect_retry_at + 1.second) { DisconnectPublisherConnectionJob.perform_now(connection.id) }
      assert connection.reload.released_at
      assert @creator.reload.deleted?
      assert @booth.reload.archived?
    end
  end

  test "E04 同じ管理者の退会で共同店舗の準備を残し唯一管理店舗だけ閉鎖する" do
    with_publisher_client do
      sole = Store.create!(name: "Sole", published: true)
      StoreMembership.create!(store: sole, user: @publisher, membership_role: :admin)
      sole_booth = Booth.create!(store: sole, name: "Sole booth", status: :offline)
      Accounts::WithdrawalService.new(user: @publisher).call!
      assert @store.reload.published?
      assert @booth.reload.standby?
      refute @booth.archived?
      refute sole.reload.published?
      assert sole_booth.reload.archived?
    end
  end

  test "E05 旧再確認経路も予定時刻を守り別ブースへ広げない" do
    with_publisher_client do
      first = issue_token
      @ivs_client.stub_responses(:disconnect_participant, "AccessDeniedException")
      cancel_token(first)
      other = build_prepared_booth("unrelated")
      assert_equal "issued", issue_token(actor: @other_publisher, stream_session: other.current_stream_session)[:state]
      @ivs_client.stub_responses(:disconnect_participant, {})
      assert Ivs::RetryPublisherDisconnectsService.new(booth: @booth, actor: @publisher).call
      connection = @stream_session.reload.current_publisher_connection
      travel_to(connection.next_disconnect_retry_at + 1.second) do
        refute Ivs::RetryPublisherDisconnectsService.new(booth: @booth, actor: @publisher).call
      end
      second = issue_token(generation: 2)
      assert_equal "issued", second[:state]
      assert_equal [ first[:participant_id] ] * 2, disconnect_requests.pluck(:participant_id)
    end
  end

  test "E04 退会後は古いUserインスタンスの認証結果でも新規接続を発行しない" do
    with_publisher_client do
      stale_actor = User.find(@publisher.id)
      ActiveRecord::Base.cache do
        assert StreamSessions::PublisherControl.active_actor?(stale_actor)
        Accounts::WithdrawalService.new(user: @publisher).call!
        assert_error("forbidden") { issue_token(actor: stale_actor) }
      end
      assert_equal 0, issued_count
    end
  end

  test "E05 キュー投入失敗は例外を返さずDBの再試行対象を保持する" do
    original = DisconnectPublisherConnectionJob.method(:set)
    failed_queue = Object.new
    failed_queue.define_singleton_method(:perform_later) { |_id| raise IOError, "queue unavailable" }
    DisconnectPublisherConnectionJob.define_singleton_method(:set) { |**_options| failed_queue }
    with_publisher_client do
      issued = issue_token
      @ivs_client.stub_responses(:disconnect_participant, "AccessDeniedException")
      cancel_token(issued)
      connection = @stream_session.reload.current_publisher_connection
      Ivs::DisconnectPublisherConnectionService.enqueue(connection.id, wait_until: connection.next_disconnect_retry_at)
      assert StreamPublisherConnection.disconnect_pending.exists?(connection.id)
      assert_nil connection.reload.released_at
    end
  ensure
    DisconnectPublisherConnectionJob.define_singleton_method(:set, original)
  end

  private

  def begin_broadcast
    issued = issue_token
    stub_published_participant(issued)
    confirm_token(issued)
    issued
  end

  def finish(actor: @publisher, request_id: nil, generation:)
    StreamSessions::EndService.new(stream_session: @stream_session, actor: actor, request_id: request_id, generation: generation).call
  end

  def archive(session_id: @stream_session.id.to_s, generation: 0)
    Booths::ArchiveService.new(booth: @booth, actor: @publisher, stream_session_id: session_id, generation: generation).call!
  end

  def assert_error(code)
    error = assert_raises(StreamSessions::PublisherControl::Error) { yield }
    assert_equal code, error.code
  end

  def create_drinks
    customer = User.create!(email: "ending-customer-#{SecureRandom.hex(5)}@example.com", password: "password", role: :customer)
    @wallet = Wallet.create!(customer_user: customer, available_points: 400, reserved_points: 100)
    item = DrinkItem.create!(store: @store, name: "Drink", price_points: 100)
    attributes = { store: @store, booth: @booth, stream_session: @stream_session, customer_user: customer, drink_item: item }
    @pending = DrinkOrder.create!(**attributes, status: :pending)
    @consumed = DrinkOrder.create!(**attributes, status: :consumed, consumed_at: Time.current)
    @hold = WalletTransaction.create!(wallet: @wallet, kind: :hold, points: -100, ref: @pending, occurred_at: Time.current)
    @ledger = StoreLedgerEntry.create!(store: @store, stream_session: @stream_session, drink_order: @consumed, points: 100, occurred_at: Time.current)
  end
end
