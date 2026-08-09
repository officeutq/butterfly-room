# frozen_string_literal: true

require "test_helper"

class LpAnalytics::Sheets::ClientTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:values, :total_updated_rows, :total_updated_cells, keyword_init: true)

  test "値を読みbatch updateをRAWで送る" do
    service = Object.new
    captured = {}
    service.define_singleton_method(:get_spreadsheet_values) do |spreadsheet_id, range|
      captured[:read] = [ spreadsheet_id, range ]
      FakeResponse.new(values: [ [ "aggregation_key" ] ])
    end
    service.define_singleton_method(:batch_update_values) do |spreadsheet_id, request|
      captured[:write] = [ spreadsheet_id, request ]
      FakeResponse.new(total_updated_rows: 1, total_updated_cells: 2)
    end
    client = LpAnalytics::Sheets::Client.new(service: service, spreadsheet_id: "dummy-spreadsheet")

    values = client.read_values("'daily_raw'!A:X")
    result = client.batch_update([
      { range: "'daily_raw'!A2:B2", values: [ [ "key", "=not-a-formula" ] ] }
    ])

    assert_equal [ [ "aggregation_key" ] ], values
    assert_equal [ "dummy-spreadsheet", "'daily_raw'!A:X" ], captured.fetch(:read)
    request = captured.fetch(:write).last
    assert_equal "RAW", request.value_input_option
    assert_equal "=not-a-formula", request.data.first.values.first.last
    assert_equal 1, result.total_updated_rows
    assert_equal 2, result.total_updated_cells
  end

  test "一時エラー時はclient呼び出しを再試行する" do
    attempts = 0
    service = Object.new
    service.define_singleton_method(:get_spreadsheet_values) do |*, **|
      attempts += 1
      raise Timeout::Error if attempts == 1

      FakeResponse.new(values: [])
    end
    policy = LpAnalytics::Sheets::RetryPolicy.new(max_attempts: 2, sleeper: ->(*) { })
    client = LpAnalytics::Sheets::Client.new(
      service: service,
      spreadsheet_id: "dummy-spreadsheet",
      retry_policy: policy
    )

    assert_equal [], client.read_values("'daily_raw'!A:X")
    assert_equal 2, attempts
  end
end
