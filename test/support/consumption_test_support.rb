module ConsumptionTestSupport
  def build_consumption_fixture
    suffix = SecureRandom.hex(6)
    @store = Store.create!(name: "Consumption #{suffix}", published: true)
    @creator, @publisher, @assigned, @outsider, @admin, @system, @customer =
      %i[cast store_admin cast cast store_admin system_admin customer].each_with_index.map do |role, i|
        User.create!(email: "consume-#{suffix}-#{i}@example.com", password: "password", role: role, display_name: "Consume #{i}")
      end
    [ @publisher, @admin ].each { |user| StoreMembership.create!(store: @store, user: user, membership_role: :admin) }
    @booth = Booth.create!(store: @store, name: "Consumption booth", status: :live,
      ivs_stage_arn: "arn:aws:ivsrealtime:ap-northeast-1:123456789012:stage/consumption")
    BoothCast.create!(booth: @booth, cast_user: @assigned)
    @session = StreamSession.create!(store: @store, booth: @booth, started_by_cast_user: @creator,
      status: :live, started_at: 10.minutes.ago, broadcast_started_at: 5.minutes.ago,
      actual_publisher_user: @publisher, actual_publisher_source: "ivs_verified", actual_publisher_recorded_at: 5.minutes.ago,
      ivs_stage_arn: @booth.ivs_stage_arn)
    @booth.update!(current_stream_session: @session)
    @wallet = Wallet.create!(customer_user: @customer, available_points: 400, reserved_points: 0)
    @item = DrinkItem.create!(store: @store, name: "Drink", price_points: 100)
    @order = add_pending_drink
  end

  def add_pending_drink(points: 100)
    order = DrinkOrder.create!(store: @store, booth: @booth, stream_session: @session,
      customer_user: @customer, drink_item: @item, status: :pending)
    @wallet.increment!(:reserved_points, points)
    WalletTransaction.create!(wallet: @wallet, kind: :hold, points: -points, ref: order, occurred_at: Time.current)
    order
  end

  def consume(order: @order, actor: @publisher)
    DrinkOrders::ConsumeService.new(drink_order_id: order.id, actor: actor).call!
  end

  def financial_snapshot
    [ @wallet.reload.attributes, DrinkOrder.where(stream_session: @session).order(:id).map(&:attributes),
      StoreLedgerEntry.where(stream_session: @session).order(:id).map(&:attributes),
      WalletTransaction.where(wallet: @wallet).order(:id).map(&:attributes), @session.comments.order(:id).map(&:attributes) ]
  end

  def cleanup_consumption_fixture
    return unless @store

    # 別接続テストで確定した、このテスト専用のレコードだけを削除する。
    Comment.where(stream_session: @session).delete_all
    StoreLedgerEntry.where(stream_session: @session).delete_all
    WalletTransaction.where(wallet: @wallet).delete_all
    DrinkOrder.where(stream_session: @session).delete_all
    Wallet.where(id: @wallet.id).delete_all
    DrinkItem.where(id: @item.id).delete_all
    @booth.update_columns(current_stream_session_id: nil)
    StreamSession.where(id: @session.id).delete_all
    BoothCast.where(booth: @booth).delete_all
    Booth.where(id: @booth.id).delete_all
    StoreMembership.where(store: @store).delete_all
    Store.where(id: @store.id).delete_all
    User.where(id: [ @creator, @publisher, @assigned, @outsider, @admin, @system, @customer ].map(&:id)).delete_all
  end
end
