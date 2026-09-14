require "test_helper"
require "timeout"
require_relative "../../support/legacy_publisher_backfill_test_support"

class StreamSessions::LegacyPublisherBackfillServiceTest < ActiveSupport::TestCase
  include LegacyPublisherBackfillTestSupport
  self.use_transactional_tests = false

  setup { build_backfill_fixture }
  teardown { cleanup_backfill_fixture }

  test "M03 plan is database read only and freezes safe values and lifetime impact" do
    add_backfill_financials
    before = backfill_snapshot
    sql = []
    callback = ->(event) { sql << event.payload[:sql] }
    manifest = ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { backfill_plan }
    assert_equal before, backfill_snapshot
    assert sql.any? { |statement| statement == "SET TRANSACTION READ ONLY" }
    assert_empty sql.grep(/\A\s*(UPDATE|INSERT|DELETE)\b/i)
    assert_equal StreamSessions::LegacyPublisherBackfillService.checksum(manifest), manifest.fetch("sha256")
    entry = manifest.fetch("entries").find { |row| row.dig("before", "id") == @session.id }
    assert_equal @creator.id, entry.dig("after", "actual_publisher_user_id")
    assert_equal 101, entry.dig("impact", "lifetime_consumed_points")
    assert_equal 3600, entry.dig("impact", "lifetime_broadcast_seconds")
    assert_equal 0, entry.dig("impact", "store_points_change")
    refute_includes JSON.generate(manifest), @creator.email
    refute_includes JSON.generate(manifest), @creator.display_name
    refute_includes JSON.generate(manifest), "participant_token"
  end

  test "M03 database rejects an accidental write during plan" do
    session_id = @session.id
    @service.define_singleton_method(:impact) do |session|
      StreamSession.where(id: session_id).update_all(title: "must not write")
      super(session)
    end
    before = backfill_snapshot
    assert_raises(ActiveRecord::StatementInvalid) { backfill_plan }
    assert_equal before, backfill_snapshot
  end

  test "M04 skips unstarted active inconsistent future and recorded sessions without exporting evidence" do
    missing_start = create_backfill_session(broadcast_started_at: nil)
    missing_end = create_backfill_session(ended_at: nil)
    reversed = create_backfill_session(ended_at: 4.hours.ago)
    active = create_backfill_session(status: :live, ended_at: nil)
    preparation = create_backfill_session(status: :live, broadcast_started_at: nil, ended_at: nil)
    future_end = create_backfill_session(ended_at: 1.day.from_now)
    future_create = create_backfill_session(created_at: 1.day.from_now)
    referenced = create_backfill_session
    @booth.update!(current_stream_session: referenced)
    verified = create_backfill_session(actual_publisher_user: @publisher, actual_publisher_source: "ivs_verified", actual_publisher_recorded_at: Time.current)
    evidence = create_backfill_session(actual_publisher_evidence: { "unknown_private_data" => "never export this" })
    before = backfill_snapshot
    manifest = backfill_plan
    reasons = manifest.fetch("excluded").to_h { |entry| [ entry.fetch("id"), entry.fetch("reason") ] }
    assert_equal "missing_broadcast_start", reasons[missing_start.id]
    assert_equal "inconsistent_end", reasons[missing_end.id]
    assert_equal "inconsistent_end", reasons[reversed.id]
    assert_equal "not_ended", reasons[active.id]
    assert_equal "not_ended", reasons[preparation.id]
    assert_equal "outside_cutoff", reasons[future_end.id]
    assert_equal "outside_cutoff", reasons[future_create.id]
    assert_equal "current_reference", reasons[referenced.id]
    assert_equal "existing_publisher_record", reasons[verified.id]
    assert_equal "existing_publisher_record", reasons[evidence.id]
    refute_includes JSON.generate(manifest), "never export this"
    run_backfill(manifest)
    assert_equal before[:sessions].reject { |row| row["id"] == @session.id }, backfill_snapshot[:sessions].reject { |row| row["id"] == @session.id }
    assert_equal before.except(:sessions), backfill_snapshot.except(:sessions)
  end

  test "M03 apply and restore change only publisher provenance and individual attribution" do
    add_backfill_financials
    before = backfill_snapshot
    manifest = backfill_plan
    with_env("ACTUAL_PUBLISHER_CONTROL_ENABLED" => "true") do
      assert_nil metrics.sole.cast_user
      assert_equal "配信者不明", ApplicationController.helpers.stream_session_publisher_name(@session)
      result = run_backfill(manifest)
      assert_equal 1, result.dig("status_counts", "applied")
      assert_equal @creator.id, @session.reload.actual_publisher_user_id
      assert_equal "legacy_creator_backfill", @session.actual_publisher_source
      assert_equal @creator.id, metrics.sole.cast_user.id
      assert_equal 101, metrics.sole.stream_sales_points
      assert_equal 3600, metrics.sole.stream_seconds
      assert_equal @creator.display_name, ApplicationController.helpers.stream_session_publisher_name(@session)
      assert_equal before.except(:sessions), backfill_snapshot.except(:sessions)
      fields = StreamSessions::LegacyPublisherBackfillService::PUBLISHER_FIELDS
      assert_equal before[:sessions].sole.except(*fields), @session.attributes.except(*fields)
      assert_equal manifest.fetch("sha256"), @session.actual_publisher_evidence.fetch("manifest_sha256")
      assert_equal 1, run_backfill(manifest, mode: "restore").dig("status_counts", "restored")
      assert_equal before, backfill_snapshot
      assert_nil metrics.sole.cast_user
      assert_equal 1, run_backfill(manifest, mode: "restore").dig("status_counts", "already_restored")
    end
  end

  test "M03 replay does not change the original application time or evidence" do
    manifest = backfill_plan
    run_backfill(manifest)
    applied = backfill_snapshot
    assert_equal 1, run_backfill(manifest).dig("status_counts", "already_applied")
    assert_equal applied, backfill_snapshot
  end

  test "M04 interrupted apply resumes the same ids without including newly created or newly ended sessions" do
    second = create_backfill_session
    later_ended = create_backfill_session(status: :live, ended_at: nil)
    manifest = backfill_plan
    assert_raises(IOError) { run_backfill(manifest) { raise IOError, "simulated interruption after commit" } }
    assert_equal @creator.id, @session.reload.actual_publisher_user_id
    assert_nil second.reload.actual_publisher_user_id
    new_session = create_backfill_session
    later_ended.update!(status: :ended, ended_at: Time.current)
    result = run_backfill(manifest)
    assert_equal 1, result.dig("status_counts", "already_applied")
    assert_equal 1, result.dig("status_counts", "applied")
    assert_nil new_session.reload.actual_publisher_user_id
    assert_nil later_ended.reload.actual_publisher_user_id
  end

  test "M04 apply skips changed source state financial impact and current booth references" do
    second = create_backfill_session
    third = create_backfill_session
    add_backfill_financials
    manifest = backfill_plan
    @session.update!(started_by_cast_user: @publisher)
    second.update!(actual_publisher_user: @publisher, actual_publisher_source: "evidence_backfill", actual_publisher_recorded_at: Time.current)
    @booth.update!(current_stream_session: third)
    before = backfill_snapshot
    result = run_backfill(manifest)
    assert_equal 2, result.dig("status_counts", "skipped_changed")
    assert_equal 1, result.dig("status_counts", "skipped_current_reference")
    assert_equal before, backfill_snapshot
    @booth.update!(current_stream_session: nil)
    manifest = backfill_plan
    StoreLedgerEntry.where(stream_session: @session).update_all(points: 102)
    before = backfill_snapshot
    assert_equal 1, run_backfill(manifest).dig("status_counts", "skipped_impact_changed")
    assert_equal before.except(:sessions), backfill_snapshot.except(:sessions)
    assert_nil @session.reload.actual_publisher_user_id
  end

  test "M04 restore never overwrites subsequent identity evidence or original history corrections" do
    second = create_backfill_session
    third = create_backfill_session
    manifest = backfill_plan
    run_backfill(manifest)
    @session.reload.update!(actual_publisher_user: @publisher, actual_publisher_source: "evidence_backfill",
      actual_publisher_evidence: { "reference" => "reviewed-correction" })
    second.update_columns(actual_publisher_evidence: second.reload.actual_publisher_evidence.merge("reviewed" => true))
    third.update_columns(ended_at: third.ended_at + 1.second)
    before = backfill_snapshot
    assert_equal 3, run_backfill(manifest, mode: "restore").dig("status_counts", "skipped_changed")
    assert_equal 3, run_backfill(manifest).dig("status_counts", "skipped_changed")
    assert_equal before, backfill_snapshot
  end

  test "invalid or unapproved manifests fail before any update" do
    manifest = backfill_plan
    before = backfill_snapshot
    assert_raises(StreamSessions::LegacyPublisherBackfillService::Error) do
      @service.run(manifest: manifest, mode: "apply", confirmation: "wrong", git_commit: @git_commit)
    end
    mutations = [
      ->(value) { value["environment"] = "another-environment" },
      ->(value) { value["database_sha256"] = "another-database" },
      ->(value) { value["entries"] << value["entries"].first.deep_dup },
      ->(value) { value["entries"] << { "before" => {} } },
      ->(value) { value["entries"].first["after"]["actual_publisher_user_id"] = @publisher.id },
      ->(value) { value["entries"].first["before"]["status"] = "live" }
    ]
    mutations.each do |mutate|
      invalid = manifest.deep_dup
      mutate.call(invalid)
      invalid["sha256"] = StreamSessions::LegacyPublisherBackfillService.checksum(invalid)
      assert_raises(StreamSessions::LegacyPublisherBackfillService::Error) { run_backfill(invalid) }
      assert_equal before, backfill_snapshot
    end
    invalid = manifest.deep_dup
    invalid["entries"].first["before"]["id"] += 1
    assert_raises(StreamSessions::LegacyPublisherBackfillService::Error) { run_backfill(invalid) }
    assert_equal before, backfill_snapshot
  end

  test "closed booths and deleted creators remain eligible historical records" do
    @booth.update!(archived_at: Time.current)
    @creator.update!(deleted_at: Time.current)
    manifest = backfill_plan
    assert_equal 1, run_backfill(manifest).dig("status_counts", "applied")
    assert_equal @creator.id, @session.reload.actual_publisher_user_id
  end

  test "each committed row survives a subsequent database failure and retry" do
    second = create_backfill_session
    manifest = backfill_plan
    second.update_columns(title: "x" * 65)
    assert_raises(ActiveRecord::RecordInvalid) { run_backfill(manifest) }
    assert_equal @creator.id, @session.reload.actual_publisher_user_id
    assert_nil second.reload.actual_publisher_user_id
    second.update_columns(title: nil)
    assert_equal({ "already_applied" => 1, "applied" => 1 }, run_backfill(manifest).fetch("status_counts"))
  end

  test "concurrent applies serialize on the booth and commit the same provenance once" do
    manifest = backfill_plan
    entered = Queue.new
    continue_first = Queue.new
    second_pid = Queue.new
    first_service = StreamSessions::LegacyPublisherBackfillService.new
    first_service.define_singleton_method(:apply_entry) do |session, **options|
      entered << true
      Timeout.timeout(20) { continue_first.pop }
      super(session, **options)
    end
    threads = []
    threads << Thread.new { ActiveRecord::Base.connection_pool.with_connection { run_backfill(manifest, service: first_service) } }
    Timeout.timeout(10) { entered.pop }
    threads << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        second_pid << connection.select_value("SELECT pg_backend_pid()")
        run_backfill(manifest, service: StreamSessions::LegacyPublisherBackfillService.new)
      end
    end
    pid = Timeout.timeout(10) { second_pid.pop }
    Timeout.timeout(10) do
      loop do
        waiting = StreamSession.uncached { StreamSession.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}") }
        break if waiting == "Lock"
        sleep 0.02
      end
    end
    continue_first << true
    results = threads.map { |thread| Timeout.timeout(20) { thread.value } }
    assert_equal({ "applied" => 1 }, results.first.fetch("status_counts"))
    assert_equal({ "already_applied" => 1 }, results.last.fetch("status_counts"))
    assert_equal @creator.id, @session.reload.actual_publisher_user_id
  ensure
    continue_first << true if continue_first
    threads&.each { |thread| thread.join(25) }
  end

  private

  def metrics
    CastMetricsQuery.new(store: @store, from: 1.day.ago, to: Time.current).call
  end
end
