module LegacyPublisherBackfillTestSupport
  def build_backfill_fixture
    suffix = SecureRandom.hex(6)
    @store = Store.create!(name: "Backfill #{suffix}")
    @creator, @publisher, @customer = %i[cast store_admin customer].each_with_index.map do |role, index|
      User.create!(email: "backfill-#{suffix}-#{index}@example.com", password: "password", role: role, display_name: "Person #{index}")
    end
    @booth = Booth.create!(store: @store, name: "Backfill booth")
    @session = create_backfill_session
    @service = StreamSessions::LegacyPublisherBackfillService.new
    @git_commit = "1234567"
  end

  def create_backfill_session(**attributes)
    StreamSession.create!({ store: @store, booth: @booth, started_by_cast_user: @creator,
      status: :ended, started_at: 3.hours.ago, broadcast_started_at: 2.hours.ago, ended_at: 1.hour.ago }.merge(attributes))
  end

  def backfill_plan
    @service.plan(git_commit: @git_commit)
  end

  def run_backfill(manifest, mode: "apply", service: @service, &block)
    service.run(manifest: manifest, mode: mode, confirmation: manifest.fetch("sha256"), git_commit: @git_commit, &block)
  end

  def add_backfill_financials
    @item = DrinkItem.create!(store: @store, name: "Old drink", price_points: 101)
    @wallet = Wallet.create!(customer_user: @customer, available_points: 500, reserved_points: 101)
    %i[consumed pending refunded].each do |status|
      order = DrinkOrder.create!(store: @store, booth: @booth, stream_session: @session,
        customer_user: @customer, drink_item: @item, status: status, consumed_at: status == :consumed ? @session.ended_at : nil)
      if status == :consumed
        StoreLedgerEntry.create!(store: @store, stream_session: @session, drink_order: order, points: 101, occurred_at: @session.ended_at)
      end
      WalletTransaction.create!(wallet: @wallet, ref: order, kind: status == :refunded ? :release : :hold,
        points: status == :refunded ? 101 : -101, occurred_at: @session.ended_at)
    end
    Comment.create!(booth: @booth, stream_session: @session, user: @creator, kind: :drink_consumed, body: "Old consumption")
    Comment.create!(booth: @booth, stream_session: @session, user: @customer, body: "Normal comment")
    Settlement.create!(store: @store, kind: :monthly, period_from: Date.yesterday, period_to: Date.tomorrow,
      gross_yen: 101, store_share_yen: 70, platform_fee_yen: 31)
  end

  def backfill_snapshot
    { sessions: StreamSession.where(store: @store).order(:id).map(&:attributes),
      booths: Booth.where(store: @store).order(:id).map(&:attributes),
      money: [ StoreLedgerEntry, DrinkOrder, Settlement ].map { |model| model.where(store: @store).order(:id).map(&:attributes) },
      comments: Comment.where(stream_session_id: StreamSession.where(store: @store).select(:id)).order(:id).map(&:attributes),
      wallets: Wallet.where(customer_user: @customer).order(:id).map(&:attributes),
      transactions: WalletTransaction.where(wallet_id: Wallet.where(customer_user: @customer).select(:id)).order(:id).map(&:attributes) }
  end

  def cleanup_backfill_fixture
    return unless @store

    session_ids = StreamSession.where(store: @store).pluck(:id)
    Comment.where(stream_session_id: session_ids).delete_all
    StoreLedgerEntry.where(store: @store).delete_all
    WalletTransaction.where(wallet_id: Wallet.where(customer_user: @customer).select(:id)).delete_all
    DrinkOrder.where(store: @store).delete_all
    Wallet.where(customer_user: @customer).delete_all
    DrinkItem.where(store: @store).delete_all
    Settlement.where(store: @store).delete_all
    Booth.where(store: @store).update_all(current_stream_session_id: nil)
    StreamSession.where(store: @store).delete_all
    Booth.where(store: @store).delete_all
    Store.where(id: @store.id).delete_all
    User.where(id: [ @creator, @publisher, @customer ].map(&:id)).delete_all
  end
end
