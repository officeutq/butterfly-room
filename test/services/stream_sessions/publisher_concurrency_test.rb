require "test_helper"

class StreamSessions::PublisherConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    suffix = SecureRandom.hex(5)
    @store = Store.create!(name: "Concurrency #{suffix}")
    @users = 2.times.map { |i| User.create!(email: "concurrent-#{suffix}-#{i}@example.test", password: "password", role: :system_admin) }
    @booths = 2.times.map { |i| Booth.create!(store: @store, name: "Concurrent #{i}", status: :offline, ivs_stage_arn: "stage-#{suffix}-#{i}") }
    @sessions = @booths.map { |booth| StreamSessions::StartService.new(booth: booth, actor: @users.first).call }
    @tokens = Queue.new
    tokens = @tokens
    @client = Object.new
    @client.define_singleton_method(:list_participants) { |**| [] }
    @client.define_singleton_method(:create_participant_token) do |**options|
      tokens << options
      Struct.new(:token, :participant_id, :expiration_time).new("token", SecureRandom.hex, 1.minute.from_now)
    end
  end

  teardown do
    # このテストが作成したテストDBのレコードだけを削除する。
    ids = @sessions.map(&:id)
    StreamPublishAttempt.where(stream_session_id: ids).delete_all
    Booth.where(id: @booths.map(&:id)).update_all(current_stream_session_id: nil)
    StreamSession.where(id: ids).delete_all
    Booth.where(id: @booths.map(&:id)).delete_all
    Store.where(id: @store.id).delete_all
    User.where(id: @users.map(&:id)).delete_all
  end

  test "two people racing for one booth issue exactly one token" do
    results = race([ [ @sessions.first, @users.first ], [ @sessions.first, @users.last ] ])
    assert_equal [ :conflict, :success ], results.sort
    assert_equal 1, @tokens.size
    assert_equal 1, StreamPublishAttempt.open.where(stream_session: @sessions).count
  end

  test "one person racing across two booths issues exactly one token" do
    results = race(@sessions.map { |session| [ session, @users.last ] })
    assert_equal [ :conflict, :success ], results.sort
    assert_equal 1, @tokens.size
    assert_equal 1, StreamPublishAttempt.open.where(user: @users.last).count
  end

  private

  def race(requests)
    ready, go = Queue.new, Queue.new
    threads = requests.map do |session, user|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          go.pop
          StreamSessions::PublishService.new(stream_session: session, actor: user,
            attempt_id: SecureRandom.uuid, client: @client).issue_token
          :success
        rescue StreamSessions::PublisherControl::Conflict
          :conflict
        end
      end
    end
    requests.size.times { ready.pop }
    requests.size.times { go << true }
    threads.map { |thread| raise "開始競合の検証がタイムアウトしました" unless thread.join(10); thread.value }
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
  end
end
