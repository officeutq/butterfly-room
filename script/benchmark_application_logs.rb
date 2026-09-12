# frozen_string_literal: true

# Run only against the test database. Synthetic rows are always rolled back.
abort "テスト環境専用です: bin/rails runner -e test script/benchmark_application_logs.rb" unless Rails.env.test?

rows = 100_000
from = (Time.current.in_time_zone("Asia/Tokyo").to_date - 179).iso8601
to = Time.current.in_time_zone("Asia/Tokyo").to_date.iso8601
common_cases = { recent: {}, actor: { from: from, to: to, actor_user_id: "42" }, store: { from: from, to: to, store_id: "12" } }

{ changes: ChangeLog, errors: ErrorLog }.each do |kind, model|
  model.connection_pool.with_connection do |connection|
    begin
      model.transaction(requires_new: true) do
        extra_columns, extra_values = if kind == :changes
          [ "target_type, target_id, action, change_data", "'Store', (n % 1000) + 1, 'updated', '{\"name\":[\"before\",\"after\"]}'::jsonb" ]
        else
          [ "severity, handled, exception_class, summary, backtrace", "'error', false, 'RuntimeError', 'safe summary', '[]'::jsonb" ]
        end
        connection.execute(<<~SQL)
          INSERT INTO #{model.table_name}
            (occurred_at, created_at, actor_user_id, store_id, source, request_id, #{extra_columns})
          SELECT CURRENT_TIMESTAMP - (n % 180) * INTERVAL '1 day' - n * INTERVAL '1 second',
            CURRENT_TIMESTAMP, (n % 100) + 1, (n % 50) + 1, 'web', 'benchmark-' || n, #{extra_values}
          FROM generate_series(1, #{rows}) AS n
        SQL
        connection.execute("ANALYZE #{model.table_name}")
        cases = common_cases.merge(
          kind == :changes ? { target: { from: from, to: to, target_type: "Store", target_id: "13" } } : { severity: { severity: "error" } }
        )
        cases[:page_1000] = { from: from, to: to, page: "1000" }
        cases.each do |name, filters|
          statement = nil
          capture = ->(_name, _start, _finish, _id, payload) do
            statement = payload if payload[:name] == "#{model.name} Load"
          end
          result = nil
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          ActiveSupport::Notifications.subscribed(capture, "sql.active_record") do
            result = Logs::SearchQuery.new(kind: kind, filters: filters).call
          end
          elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
          raise "検索失敗: #{result.errors}" if result.errors.any? || !statement

          plan = connection.exec_query("EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) #{statement[:sql]}", "Log benchmark", statement[:binds]).first.fetch("QUERY PLAN")
          plan = JSON.parse(plan) if plan.is_a?(String)
          puts({ kind: kind, rows_added: rows, case: name, returned: result.records.size,
            query_ms: elapsed.round(2), plan: plan }.to_json)
        end
        raise ActiveRecord::Rollback
      end
    ensure
      connection.execute("ANALYZE #{model.table_name}")
    end
  end
end
