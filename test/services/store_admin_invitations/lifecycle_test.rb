require "test_helper"
require "timeout"

class StoreAdminInvitations::LifecycleTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @store = Store.create!(name: "招待競合確認 #{SecureRandom.hex(4)}")
    @admin = User.create!(email: "invite-race-#{SecureRandom.hex(6)}@example.test", password: "password", role: :store_admin)
    @recipient = User.create!(email: "invite-recipient-#{SecureRandom.hex(6)}@example.test", password: "password", role: :store_admin)
    StoreMembership.create!(store: @store, user: @admin, membership_role: :admin)
    @invitation = StoreAdminInvitations::IssueInvitation.call!(store: @store, invited_by_user: @admin).invitation
  end

  teardown do
    StoreAdminInvitation.where(store: @store).delete_all
    StoreMembership.where(store: @store).delete_all
    Store.where(id: @store.id).delete_all
    User.where(id: [ @admin.id, @recipient.id ]).delete_all
  end

  test "concurrent requests with one key create one invitation and return the same URL" do
    key = SecureRandom.uuid
    barrier = Queue.new
    workers = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Timeout.timeout(10) { barrier.pop }
          StoreAdminInvitations::IssueInvitation.call!(store: @store, invited_by_user: User.find(@admin.id),
            request_key: key, url_builder: ->(token) { "https://example.test/invite/#{token}" }).invitation
        end
      end
    end
    2.times { barrier << true }
    results = workers.map { |worker| Timeout.timeout(10) { worker.value } }
    assert_equal 1, results.map(&:id).uniq.size
    assert_equal 1, results.map(&:issued_url).uniq.size
    assert results.first.issued_url.present?
    assert_equal 1, StoreAdminInvitation.where(invited_by_user: @admin, request_key: key).count
  ensure
    workers&.each { |worker| worker.join(10) || worker.kill }
  end

  test "failed URL persistence rolls back invitation and same key cannot move to another store" do
    key = SecureRandom.uuid
    assert_no_difference "StoreAdminInvitation.count" do
      assert_raises(RuntimeError) do
        StoreAdminInvitations::IssueInvitation.call!(store: @store, invited_by_user: @admin,
          request_key: key, url_builder: ->(_) { raise "URL保存失敗" })
      end
    end
    StoreAdminInvitations::IssueInvitation.call!(store: @store, invited_by_user: @admin, request_key: key)
    other = Store.create!(name: "別店舗")
    StoreMembership.create!(store: other, user: @admin, membership_role: :admin)
    assert_raises(ArgumentError) { StoreAdminInvitations::IssueInvitation.call!(store: other, invited_by_user: @admin, request_key: key) }
  ensure
    StoreMembership.where(store: other).delete_all if other
    other&.destroy!
  end

  test "cancel winning the lock rejects acceptance without creating membership" do
    verify_race(:cancel, :accept, StoreAdminInvitations::AcceptInvitation::NotUsable)
    assert @invitation.reload.cancelled?
    assert_not @invitation.used?
    assert_not StoreMembership.exists?(store: @store, user: @recipient)
  end

  test "accept winning the lock rejects cancel and preserves membership" do
    verify_race(:accept, :cancel, StoreAdminInvitations::UpdateInvitation::Conflict)
    assert @invitation.reload.used?
    assert_not @invitation.cancelled?
    assert StoreMembership.exists?(store: @store, user: @recipient)
  end

  test "share winning the lock prevents cancellation" do
    verify_race(:shared, :cancel, StoreAdminInvitations::UpdateInvitation::Conflict)
    assert @invitation.reload.shared_at
    assert_not @invitation.cancelled?
  end

  test "cancel winning the lock prevents recording a share" do
    verify_race(:cancel, :shared, StoreAdminInvitations::UpdateInvitation::Conflict)
    assert_nil @invitation.reload.shared_at
  end

  test "existing member auto acceptance rechecks cancellation under lock" do
    StoreMembership.create!(store: @store, user: @recipient, membership_role: :admin)
    verify_race(:cancel, :existing_member, NilClass)
    assert_not @invitation.reload.used?
  end

  test "service rejects permissions lost after request was authorized" do
    StoreMembership.where(store: @store, user: @admin).delete_all
    assert_raises(StoreAdminInvitations::IssueInvitation::NotAuthorized) do
      StoreAdminInvitations::IssueInvitation.call!(store: @store, invited_by_user: @admin)
    end
    assert_raises(StoreAdminInvitations::UpdateInvitation::NotAuthorized) do
      operation(:cancel)
    end
    assert_not @invitation.reload.cancelled?
  end

  private

  def operation(action)
    invitation = StoreAdminInvitation.find(@invitation.id)
    case action
    when :accept
      StoreAdminInvitations::AcceptInvitation.call!(invitation: invitation, actor: @recipient)
    when :existing_member
      StoreAdminInvitations::AcceptInvitation.accept_if_member!(invitation: invitation, actor: @recipient)
    else
      StoreAdminInvitations::UpdateInvitation.call!(invitation: invitation, actor: @admin, action: action)
    end
  end

  def verify_race(first, second, expected)
    started = Queue.new
    worker = nil
    StoreAdminInvitation.transaction do
      operation(first)
      worker = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          started << connection.select_value("SELECT pg_backend_pid()")
          operation(second)
        rescue StoreAdminInvitations::UpdateInvitation::Conflict, StoreAdminInvitations::AcceptInvitation::NotUsable => error
          error
        end
      end
      pid = Timeout.timeout(10) { started.pop }
      ActiveRecord::Base.uncached do
        Timeout.timeout(10) do
          loop do
            ActiveRecord::Base.connection.execute("SELECT pg_stat_clear_snapshot()")
            state = ActiveRecord::Base.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}")
            break if state == "Lock"
            sleep 0.01
          end
        end
      end
    end
    assert_kind_of expected, Timeout.timeout(10) { worker.value }
  ensure
    worker&.join(10) || worker&.kill
  end
end
