# frozen_string_literal: true

# bin/rails runner script/inventory_legacy_publishers.rb
# 新列の導入前でも使用できる読み取り専用の旧履歴調査。人物の確定・補完は行わない。
require "json"

begin
  expected_database = ENV.fetch("PUBLISHER_AUDIT_EXPECTED_DATABASE")
  connection = ActiveRecord::Base.connection
  raise "outer transaction" if connection.transaction_open?
  inventory = ActiveRecord::Base.transaction(isolation: :repeatable_read) do
    connection.execute("SET TRANSACTION READ ONLY")
    connection.execute("SET LOCAL statement_timeout = '10s'")
    database = connection.select_value("SELECT current_database()")
    raise "database mismatch" unless database == expected_database
    columns = connection.columns(:stream_sessions).map(&:name)
    fields = %w[id store_id booth_id started_by_cast_user_id status started_at broadcast_started_at ended_at created_at updated_at ivs_stage_arn]
    fields += %w[actual_publisher_user_id actual_publisher_source actual_publisher_recorded_at].select { |name| columns.include?(name) }
    sessions = connection.select_all("SELECT #{fields.map { |name| connection.quote_column_name(name) }.join(', ')} FROM stream_sessions ORDER BY id").to_a
    booths = connection.select_all("SELECT id, status, current_stream_session_id FROM booths WHERE current_stream_session_id IS NOT NULL").to_a
    current = booths.group_by { |booth| booth.fetch("current_stream_session_id") }
    ledger = connection.select_all("SELECT stream_session_id, COUNT(*) AS count, SUM(points) AS points, MIN(occurred_at) AS first_at, MAX(occurred_at) AS last_at FROM store_ledger_entries GROUP BY stream_session_id").to_a.index_by { |row| row.fetch("stream_session_id") }
    comments = connection.select_all("SELECT id, stream_session_id, user_id, kind, created_at, deleted_at FROM comments WHERE kind = 'drink_consumed' ORDER BY id").to_a

    entries = sessions.map do |session|
      references = current.fetch(session.fetch("id"), [])
      state = if references.size > 1 || references.any? { |booth| booth.fetch("id") != session.fetch("booth_id") }
        "inconsistent_current_reference"
      elsif session.fetch("status") == StreamSession.statuses.fetch("ended")
        if session["ended_at"].nil? || (session["broadcast_started_at"] && session["ended_at"] < session["broadcast_started_at"])
          "inconsistent_end"
        elsif references.any?
          "inconsistent_current_reference"
        elsif session["broadcast_started_at"]
          "ended_with_start"
        else
          "ended_without_start"
        end
      elsif references.empty?
        "unreferenced_unended"
      elsif references.any? { |booth| [ Booth.statuses.fetch("live"), Booth.statuses.fetch("away") ].include?(booth.fetch("status")) }
        "active_broadcast"
      elsif session["broadcast_started_at"].nil? && references.sole.fetch("status") == Booth.statuses.fetch("standby")
        "preparation_without_start"
      else
        "inconsistent_active_state"
      end
      session.merge("classification" => state, "ledger" => ledger[session.fetch("id")],
        "current_booth_ids" => references.map { |booth| booth.fetch("id") })
    end
    log_ranges = %w[change_logs error_logs].filter_map do |table|
      next unless connection.data_source_exists?(table)
      range = connection.select_one("SELECT COUNT(*) AS count, MIN(occurred_at) AS first_at, MAX(occurred_at) AS last_at, COUNT(stream_session_id) AS session_reference_count FROM #{connection.quote_table_name(table)}")
      [ table, range ]
    end.to_h
    {
      schema_version: 1, environment: Rails.env.to_s, app_env: ENV["APP_ENV"], database: database,
      observed_at: connection.select_value("SELECT CURRENT_TIMESTAMP"), publisher_columns_present: columns.include?("actual_publisher_user_id"),
      session_count: entries.size, classifications: entries.map { |entry| entry.fetch("classification") }.tally,
      consumed_points: ledger.values.sum { |row| row.fetch("points").to_i },
      consumption_comment_count: comments.size, log_ranges: log_ranges,
      entries: entries, consumption_comments: comments
    }
  end
  # 生のコメント本文・任意のevidence・トークン・アカウント情報は出力しない。
  normalize = lambda do |value|
    case value
    when Hash then value.transform_values { |item| normalize.call(item) }
    when Array then value.map { |item| normalize.call(item) }
    when Time, DateTime, ActiveSupport::TimeWithZone then value.to_time.utc.iso8601(6)
    else value
    end
  end
  puts JSON.pretty_generate(normalize.call(inventory))
rescue StandardError => error
  warn JSON.generate(event: "legacy_publisher_inventory_failed", error_class: error.class.name)
  exit 1
end
