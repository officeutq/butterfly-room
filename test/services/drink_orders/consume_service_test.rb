require "test_helper"

class DrinkOrders::ConsumeServiceTest < ActiveSupport::TestCase
  setup do
    @store = Store.create!(name: "Consumption")
    @x = User.create!(email: "consume-x@example.test", password: "password", role: :cast)
    @y = User.create!(email: "consume-y@example.test", password: "password", role: :cast)
    @customer = User.create!(email: "consume-customer@example.test", password: "password", role: :customer)
    @wallet = Wallet.create!(customer_user: @customer, available_points: 1_000, reserved_points: 0)
    @booth = Booth.create!(store: @store, name: "Consumption", status: :live)
    @session = StreamSession.create!(store: @store, booth: @booth, status: :live, started_by_cast_user: @x,
      started_at: 20.minutes.ago, broadcast_started_at: 10.minutes.ago, broadcast_started_by_user: @y)
    @booth.update!(current_stream_session: @session)
    @item = DrinkItem.create!(store: @store, name: "Drink", price_points: 300, enabled: true)
  end

  test "consumption belongs to Y and money remains based on consumption only" do
    order = DrinkOrders::CreateService.new(stream_session: @session, customer_user: @customer, drink_item: @item).call!.drink_order
    assert_equal 0, StoreLedgerEntry.where(stream_session: @session).sum(:points)
    assert_equal 300, @wallet.reload.reserved_points
    DrinkOrders::ConsumeService.new(drink_order_id: order.id).call!
    comment = @session.comments.where(kind: Comment::KIND_DRINK_CONSUMED).sole
    assert_equal @y.id, comment.user_id
    assert order.reload.consumed?
    assert_equal 300, StoreLedgerEntry.where(stream_session: @session).sum(:points)
    assert_equal 0, @wallet.reload.reserved_points
    assert_equal 700, @wallet.available_points
    assert_raises(DrinkOrders::ConsumeService::InvalidStatusError) { DrinkOrders::ConsumeService.new(drink_order_id: order.id).call! }
  end

  test "unknown broadcaster uses an unattributed system notification and never fails after committing money" do
    @session.update!(broadcast_started_by_user: nil)
    order = DrinkOrders::CreateService.new(stream_session: @session, customer_user: @customer, drink_item: @item).call!.drink_order
    DrinkOrders::ConsumeService.new(drink_order_id: order.id).call!
    comment = @session.comments.where(kind: Comment::KIND_DRINK_CONSUMED).sole
    assert_nil comment.user_id
    assert_equal 300, StoreLedgerEntry.where(stream_session: @session).sum(:points)
    assert @session.comments.new(booth: @booth, user: nil, kind: Comment::KIND_CHAT, body: "匿名不可").invalid?
  end
end
