require "test_helper"
require_relative "../../support/legacy_publisher_backfill_test_support"

class LegacyPublisherInventoryTest < ActiveSupport::TestCase
  include LegacyPublisherBackfillTestSupport
  self.use_transactional_tests = false

  setup { build_backfill_fixture }
  teardown { cleanup_backfill_fixture }

  test "inventory is read only and distinguishes preparation history and inconsistent references" do
    add_backfill_financials
    preparation = create_backfill_session(status: :live, broadcast_started_at: nil, ended_at: nil)
    @booth.update!(status: :standby, current_stream_session: preparation)
    unreferenced = create_backfill_session(status: :live, ended_at: nil)
    missing_start = create_backfill_session(broadcast_started_at: nil)
    foreign_booth = Booth.create!(store: @store, name: "Wrong reference", status: :live, current_stream_session: unreferenced)
    sql = []
    before = backfill_snapshot
    inventory = ActiveSupport::Notifications.subscribed(->(event) { sql << event.payload[:sql] }, "sql.active_record") { run_inventory }
    entries = inventory.fetch("entries").index_by { |entry| entry.fetch("id") }
    assert_equal "ended_with_start", entries.fetch(@session.id).fetch("classification")
    assert_equal "preparation_without_start", entries.fetch(preparation.id).fetch("classification")
    assert_equal "ended_without_start", entries.fetch(missing_start.id).fetch("classification")
    assert_equal "inconsistent_current_reference", entries.fetch(unreferenced.id).fetch("classification")
    assert_equal [ foreign_booth.id ], entries.fetch(unreferenced.id).fetch("current_booth_ids")
    assert_equal @session.broadcast_started_at.utc.iso8601(6), entries.fetch(@session.id).fetch("broadcast_started_at")
    assert_equal 101, inventory.fetch("consumed_points")
    assert_equal 1, inventory.fetch("consumption_comment_count")
    assert inventory.fetch("publisher_columns_present")
    assert sql.include?("SET TRANSACTION READ ONLY")
    assert_empty sql.grep(/\A\s*(UPDATE|INSERT|DELETE)\b/i)
    assert_equal before, backfill_snapshot
    refute_includes JSON.generate(inventory), @creator.email
    refute_includes JSON.generate(inventory), "Old consumption"
    refute_includes JSON.generate(inventory), "Normal comment"
  end

  test "inventory rejects a different database before scanning business data" do
    before = backfill_snapshot
    error = nil
    stdout, stderr = capture_io do
      with_env("PUBLISHER_AUDIT_EXPECTED_DATABASE" => "another_database") do
        error = assert_raises(SystemExit) { load Rails.root.join("script/inventory_legacy_publishers.rb") }
      end
    end
    assert_equal 1, error.status
    assert_empty stdout
    assert_equal "legacy_publisher_inventory_failed", JSON.parse(stderr).fetch("event")
    assert_equal before, backfill_snapshot
  end

  test "inventory can read the column set before the publisher migration" do
    connection = ActiveRecord::Base.connection
    original = connection.method(:columns)
    connection.define_singleton_method(:columns) do |table_name|
      columns = original.call(table_name)
      table_name.to_s == "stream_sessions" ? columns.reject { |column| column.name.start_with?("actual_publisher_") } : columns
    end
    inventory = run_inventory
    refute inventory.fetch("publisher_columns_present")
    refute inventory.fetch("entries").first.key?("actual_publisher_user_id")
  ensure
    connection.define_singleton_method(:columns, original) if original
  end

  private

  def run_inventory
    database = ActiveRecord::Base.connection.select_value("SELECT current_database()")
    stdout, = capture_io do
      with_env("PUBLISHER_AUDIT_EXPECTED_DATABASE" => database) do
        load Rails.root.join("script/inventory_legacy_publishers.rb")
      end
    end
    JSON.parse(stdout)
  end
end
