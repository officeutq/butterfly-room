require "test_helper"
require_relative "../../support/publisher_connection_test_support"

class Cast::PublisherFullFlowTest < ActionDispatch::IntegrationTest
  include PublisherConnectionTestSupport

  setup do
    build_publisher_fixture
    @creator.update!(display_name: "Creator X")
    @publisher.update!(display_name: "Publisher Y")
    @assigned = User.create!(email: "flow-z-#{SecureRandom.hex(6)}@example.com", password: "password",
      role: :cast, display_name: "Assigned Z")
    BoothCast.where(booth: @booth).delete_all
    BoothCast.create!(booth: @booth, cast_user: @assigned)
    @customer = User.create!(email: "flow-viewer-#{SecureRandom.hex(6)}@example.com", password: "password", role: :customer)
    @wallet = Wallet.create!(customer_user: @customer, available_points: 800, reserved_points: 0)
    @item = DrinkItem.create!(store: @store, name: "Flow drink", price_points: 100)
    sign_in @publisher, scope: :user
  end

  test "旧準備XをYが再利用し再接続後の消化・通知・終了・履歴・売上もYへ一貫させ担当Zを保つ" do
    with_publisher_client do
      untouched = build_prepared_booth("untouched-#{SecureRandom.hex(4)}").current_stream_session
      old_preparation = untouched.attributes
      before = @stream_session.attributes
      assert_nil @stream_session.actual_publisher_user_id
      assert_empty StreamSession.actually_broadcasting_by(@creator)
      post cast_current_booth_path, params: { booth_id: @booth.id, return_to_key: "booth_show" }
      post enter_as_cast_booth_path(@booth)
      assert_redirected_to live_cast_booth_path(@booth)
      follow_redirect!
      assert_response :ok
      assert_equal before, @stream_session.reload.attributes

      first = request_token(0)
      assert_nil @stream_session.reload.actual_publisher_user_id
      stub_published_participant(first)
      started = Time.current.change(usec: 0)
      travel_to started do
        confirm_over_http(first)
      end
      assert_equal [ @stream_session.id ], StreamSession.actually_broadcasting_by(@publisher).pluck(:id)
      assert_empty StreamSession.actually_broadcasting_by(@creator)
      assert_empty StreamSession.actually_broadcasting_by(@assigned)
      assert_equal started, @stream_session.reload.broadcast_started_at

      travel_to started + 1.minute do
        change_state("away", first)
        assert @booth.reload.away?
        change_state("live", first)
        second = request_token(first[:generation])
        assert_equal [ first[:participant_id] ], disconnect_requests.pluck(:participant_id)
        stub_published_participant(second)
        confirm_over_http(second)
        assert_equal started, @stream_session.reload.broadcast_started_at
        post finish_cast_stream_session_path(@stream_session), params: first.slice(:request_id, :generation), as: :json
        assert_response :conflict
        assert @booth.reload.live?

        consumed = pending_drink
        refunded = pending_drink
        sign_in @other_publisher, scope: :user
        post consume_cast_drink_order_path(consumed), as: :json
        assert_response :forbidden
        sign_in @publisher, scope: :user
        post consume_cast_drink_order_path(consumed), as: :json
        assert_response :ok
        notification = Comment.find_by!(drink_order: consumed)
        assert_equal @publisher.id, notification.user_id
        assert_equal Comment::KIND_DRINK_CONSUMED, notification.kind
        post consume_cast_drink_order_path(consumed), as: :json
        assert_response :conflict
        assert_equal 1, StoreLedgerEntry.where(stream_session: @stream_session).count

        chat = Comment.create!(stream_session: @stream_session, booth: @booth, user: @customer, body: "flow chat")
        patch hide_stream_session_comment_path(@stream_session, chat)
        assert_response :ok
        assert_equal @publisher.id, chat.reload.metadata["hidden_by_user_id"]
        patch unhide_stream_session_comment_path(@stream_session, chat)
        assert_response :ok
        assert_equal @customer.id, chat.reload.user_id

        travel 4.minutes
        post finish_cast_stream_session_path(@stream_session), params: second.slice(:request_id, :generation), as: :json
        assert_response :ok
        assert consumed.reload.consumed?
        assert refunded.reload.refunded?
        assert_equal 100, WalletTransaction.find_by!(ref: refunded, kind: :release).points
        assert_equal 0, @wallet.reload.reserved_points
        assert_equal 900, @wallet.available_points
        assert_equal [ first[:participant_id], second[:participant_id] ], disconnect_requests.pluck(:participant_id)
      end

      assert @stream_session.reload.ended?
      assert_equal @creator.id, @stream_session.started_by_cast_user_id
      assert_equal @publisher.id, @stream_session.actual_publisher_user_id
      assert_equal @assigned.id, @booth.primary_cast_user.id
      assert_equal started, @stream_session.broadcast_started_at
      assert_nil @booth.reload.current_stream_session_id
      assert_equal old_preparation, untouched.reload.attributes
      assert_empty StreamSession.actually_broadcasting_by(@publisher)
      assert_empty StreamPublisherConnection.unreleased.where(user: @publisher)

      ledger_before = StoreLedgerEntry.where(stream_session: @stream_session).map(&:attributes)
      get cast_stream_session_path(@stream_session)
      assert_response :ok
      assert_select ".card-body", text: /Publisher Y/
      get cast_booth_stream_sessions_path(@booth)
      assert_response :ok
      assert_select "a[href='#{cast_stream_session_path(@stream_session)}']", text: /Publisher Y/
      get share_booth_path(@booth, stream: @stream_session.id)
      assert_response :ok
      assert_select "meta[property='og:description'][content='Publisher Yのライブ配信をButterflyveで楽しもう']", count: 1
      get share_booth_path(@booth)
      assert_select "meta[property='og:description'][content='Assigned Zのライブ配信をButterflyveで楽しもう']", count: 1
      row = CastMetricsQuery.new(store: @store, from: started - 1.hour, to: started + 1.hour).call.sole
      assert_equal @publisher.id, row.cast_user.id
      assert_equal 100, row.stream_sales_points
      assert_equal 300, row.stream_seconds
      assert_equal ledger_before, StoreLedgerEntry.where(stream_session: @stream_session).map(&:attributes)
    end
  end

  private

  def request_token(generation)
    post stream_session_ivs_participant_tokens_path(@stream_session), params: {
      role: "publisher", request_id: SecureRandom.uuid, expected_generation: generation }, as: :json
    assert_response :ok
    response.parsed_body.symbolize_keys
  end

  def confirm_over_http(issued)
    patch start_broadcast_cast_stream_session_path(@stream_session), params: issued.slice(:request_id, :generation), as: :json
    assert_response :ok
    assert_equal @publisher.id, response.parsed_body["actual_publisher_user_id"]
  end

  def change_state(state, issued)
    patch status_cast_booth_path(@booth), params: issued.slice(:request_id, :generation).merge(
      to: state, stream_session_id: @stream_session.id), as: :json
    assert_response :ok
  end

  def pending_drink
    order = DrinkOrder.create!(store: @store, booth: @booth, stream_session: @stream_session,
      customer_user: @customer, drink_item: @item, status: :pending)
    @wallet.increment!(:reserved_points, 100)
    WalletTransaction.create!(wallet: @wallet, kind: :hold, points: -100, ref: order, occurred_at: Time.current)
    order
  end
end
