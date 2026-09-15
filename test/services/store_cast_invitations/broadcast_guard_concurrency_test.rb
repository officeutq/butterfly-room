require "test_helper"
require "timeout"
require_relative "../../support/publisher_connection_test_support"

class StoreCastInvitations::BroadcastGuardConcurrencyTest < ActiveSupport::TestCase
  include PublisherConnectionTestSupport
  self.use_transactional_tests = false

  setup do
    build_publisher_fixture
    @creator.update!(role: :store_admin)
    @publisher.update!(role: :cast)
    StoreMembership.where(store: @store, user: @publisher).update_all(membership_role: :cast)
    StoreMembership.create!(store: @store, user: @creator, membership_role: :admin)
    BoothCast.where(booth: @booth).update_all(cast_user_id: @publisher.id)
    @invited_store = Store.create!(name: "Invitation race #{SecureRandom.hex(6)}")
    StoreMembership.create!(store: @invited_store, user: @other_publisher, membership_role: :admin)
    @invitation = StoreCastInvitations::IssueInvitation.call!(store: @invited_store,
      invited_by_user: @other_publisher).invitation
    @stage_calls = []
    calls = @stage_calls
    @stage_client = Object.new
    @stage_client.define_singleton_method(:create_stage!) do |name:, tags: {}|
      calls << name
      "arn:aws:ivs:ap-northeast-1:123456789012:stage/#{name}"
    end
    Ivs::Client.factory = ->(region:) { @stage_client }
  end

  teardown do
    Ivs::Client.reset_factory!
    # 別DB接続で確定させた、このテストの2店舗の記録だけを片付ける。
    store_ids = [ @store.id, @invited_store.id ]
    booth_ids = Booth.where(store_id: store_ids).pluck(:id)
    session_ids = StreamSession.where(store_id: store_ids).pluck(:id)
    Booth.where(id: booth_ids).update_all(current_stream_session_id: nil)
    StreamSession.where(id: session_ids).update_all(current_publisher_connection_id: nil)
    StreamPublisherConnection.where(stream_session_id: session_ids).delete_all
    StreamSession.where(id: session_ids).delete_all
    BoothCast.where(booth_id: booth_ids).delete_all
    Booth.where(id: booth_ids).delete_all
    StoreCastInvitation.where(store_id: store_ids).delete_all
    StoreMembership.where(store_id: store_ids).delete_all
    User.where(id: [ @creator.id, @publisher.id, @other_publisher.id ]).delete_all
    Store.where(id: store_ids).delete_all
  end

  test "開始成功の確定が先なら待機中の招待承認は副作用なしで拒否する" do
    verify_race(first: :confirm)
  end

  test "招待承認が先なら未確定の開始権を配信中とみなさず承認を完了する" do
    verify_race(first: :accept)
  end

  test "既に所属済みの表示経路も開始確定を待って招待の消費を拒否する" do
    StoreMembership.create!(store: @invited_store, user: @publisher, membership_role: :cast)
    verify_race(first: :confirm, already_member: true)
  end

  private

  def verify_race(first:, already_member: false)
    entered = Queue.new
    proceed = Queue.new
    waiting = Queue.new
    threads = []
    client = first == :confirm ? @ivs_client : @stage_client
    operation = first == :confirm ? :get_participant : :create_stage!
    original = client.method(operation)
    client.define_singleton_method(operation) do |**arguments|
      response = original.call(**arguments)
      entered << ActiveRecord::Base.connection.select_value("SELECT pg_backend_pid()")
      Timeout.timeout(30) { proceed.pop }
      response
    end

    with_env("MANUAL_CAPTURE_FAKE_IVS" => "0") do
      with_publisher_client do
        issued = issue_token
        stub_published_participant(issued)
        threads << run_operation(first, issued, already_member: already_member)
        first_pid = Timeout.timeout(10) { entered.pop }
        threads << run_operation(first == :confirm ? :accept : :confirm, issued,
          already_member: already_member, pid_queue: waiting)
        second_pid = Timeout.timeout(10) { waiting.pop }
        refute_equal first_pid, second_pid
        wait_for_database_lock(second_pid)
        proceed << true
        results = threads.map { |thread| Timeout.timeout(10) { thread.value } }

        assert @booth.reload.live?
        assert_equal @publisher.id, @stream_session.reload.actual_publisher_user_id
        assert_empty disconnect_requests
        if first == :confirm
          assert_equal "confirmed", results.first[:state]
          assert_equal StoreCastInvitations::AcceptInvitation::Broadcasting.name, results.last[:error]
          assert_not @invitation.reload.used?
          assert_empty @stage_calls
          assert_equal 0, Booth.where(store: @invited_store).count
          assert_equal already_member, StoreMembership.exists?(store: @invited_store, user: @publisher, membership_role: :cast)
        else
          assert_equal @invited_store.id, results.first.booth.store_id
          assert_equal "confirmed", results.last[:state]
          assert @invitation.reload.used?
          assert_equal 1, @stage_calls.size
          assert_equal 1, Booth.where(store: @invited_store).count
          assert StoreMembership.exists?(store: @invited_store, user: @publisher, membership_role: :cast)
        end
      end
    end
  ensure
    proceed << true
    threads.each { |thread| thread.join(10) || thread.kill }
    client.define_singleton_method(operation, original)
  end

  def run_operation(action, issued, already_member:, pid_queue: nil)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        actor = User.find(@publisher.id)
        pid_queue << connection.select_value("SELECT pg_backend_pid()") if pid_queue
        if action == :confirm
          StreamSessions::ConfirmPublisherService.new(stream_session: StreamSession.find(@stream_session.id),
            actor: actor, request_id: issued[:request_id], generation: issued[:generation]).call
        elsif already_member
          StoreCastInvitations::AcceptInvitation.consume_if_already_member!(
            invitation: StoreCastInvitation.find(@invitation.id), actor: actor)
        else
          StoreCastInvitations::AcceptInvitation.call!(invitation: StoreCastInvitation.find(@invitation.id), actor: actor)
        end
      rescue StoreCastInvitations::AcceptInvitation::NotAuthorized => error
        { error: error.class.name }
      end
    end
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
end
