# frozen_string_literal: true

require "test_helper"

class LpAnalytics::Sheets::IdempotentWriterTest < ActiveSupport::TestCase
  TARGET_DATE = Date.new(2026, 8, 9)
  EXPORTED_AT = Time.zone.parse("2026-08-10 02:20:00")

  class MemoryClient
    attr_reader :values, :batch_calls

    def initialize(values = [])
      @values = Marshal.load(Marshal.dump(values))
      @batch_calls = []
    end

    def read_values(_range)
      Marshal.load(Marshal.dump(values))
    end

    def batch_update(updates)
      batch_calls << Marshal.load(Marshal.dump(updates))
      updates.each do |update|
        row_number = update.fetch(:range).match(/A(\d+):[A-Z]+\d+\z/)[1].to_i
        values.fill([], values.length...row_number)
        values[row_number - 1] = update.fetch(:values).first.dup
      end
      LpAnalytics::Sheets::Client::Result.new(
        total_updated_rows: updates.length,
        total_updated_cells: updates.length * LpAnalytics::Sheets::IdempotentWriter::HEADERS.length
      )
    end
  end

  test "初回はheaderと集計行を書き同じ日を再実行しても行を増やさない" do
    client = MemoryClient.new
    writer = writer(client)
    rows = [ build_row(key: "a"), build_row(key: "b", traffic_source: "meta") ]

    first = writer.call(rows: rows, aggregation_date: TARGET_DATE, exported_at: EXPORTED_AT)
    second = writer.call(rows: rows, aggregation_date: TARGET_DATE, exported_at: EXPORTED_AT + 1.hour)

    assert_equal 2, first.row_count
    assert_equal 3, client.values.length
    assert_equal LpAnalytics::Sheets::IdempotentWriter::HEADERS, client.values.first
    assert_equal %w[a b], client.values.drop(1).map(&:first).sort
    assert_equal 2, second.row_count
    assert_equal 3, client.values.length
  end

  test "既存keyは同じ行で更新する" do
    client = MemoryClient.new
    writer = writer(client)
    writer.call(rows: [ build_row(key: "same", visit_count: 1) ], aggregation_date: TARGET_DATE, exported_at: EXPORTED_AT)
    original_length = client.values.length

    writer.call(rows: [ build_row(key: "same", visit_count: 9) ], aggregation_date: TARGET_DATE, exported_at: EXPORTED_AT)

    assert_equal original_length, client.values.length
    visit_count_column = LpAnalytics::Sheets::IdempotentWriter::HEADERS.index("lp_visit_count")
    assert_equal 9, client.values.second.fetch(visit_count_column)
  end

  test "再集計で消えた対象日行を空欄化し他の日付は維持する" do
    client = MemoryClient.new
    writer = writer(client)
    writer.call(
      rows: [ build_row(key: "keep"), build_row(key: "remove") ],
      aggregation_date: TARGET_DATE,
      exported_at: EXPORTED_AT
    )
    other_date_row = build_row(key: "other-date", aggregation_date: TARGET_DATE - 1.day)
    client.values << sheet_values(other_date_row)

    writer.call(rows: [ build_row(key: "keep") ], aggregation_date: TARGET_DATE, exported_at: EXPORTED_AT)

    assert client.values.find { |values| values.first == "remove" }.nil?
    assert client.values.any? { |values| values.first == "other-date" }
    assert client.values.any? { |values| values.all?(&:blank?) }
  end

  test "対象日が0行になった場合も既存対象日行を空欄化する" do
    client = MemoryClient.new
    writer = writer(client)
    writer.call(rows: [ build_row(key: "remove") ], aggregation_date: TARGET_DATE, exported_at: EXPORTED_AT)

    result = writer.call(rows: [], aggregation_date: TARGET_DATE, exported_at: EXPORTED_AT)

    assert_equal 0, result.row_count
    assert client.values.second.all?(&:blank?)
  end

  test "header不一致と既存duplicate keyでは書き込まない" do
    invalid_header_client = MemoryClient.new([ [ "wrong" ] ])
    assert_raises LpAnalytics::Sheets::IdempotentWriter::HeaderMismatchError do
      writer(invalid_header_client).call(rows: [], aggregation_date: TARGET_DATE, exported_at: EXPORTED_AT)
    end
    assert_empty invalid_header_client.batch_calls

    duplicate_values = [
      LpAnalytics::Sheets::IdempotentWriter::HEADERS,
      sheet_values(build_row(key: "duplicate")),
      sheet_values(build_row(key: "duplicate"))
    ]
    duplicate_client = MemoryClient.new(duplicate_values)
    assert_raises LpAnalytics::Sheets::IdempotentWriter::DuplicateAggregationKeyError do
      writer(duplicate_client).call(rows: [], aggregation_date: TARGET_DATE, exported_at: EXPORTED_AT)
    end
    assert_empty duplicate_client.batch_calls
  end

  test "途中欠損した管理行では書き込まない" do
    partial_client = MemoryClient.new([
      LpAnalytics::Sheets::IdempotentWriter::HEADERS,
      [ "partial-key", TARGET_DATE.iso8601 ]
    ])

    assert_raises LpAnalytics::Sheets::IdempotentWriter::SheetStructureError do
      writer(partial_client).call(rows: [], aggregation_date: TARGET_DATE, exported_at: EXPORTED_AT)
    end
    assert_empty partial_client.batch_calls
  end

  test "API応答の更新行数・セル数不一致を失敗にする" do
    client = MemoryClient.new
    client.define_singleton_method(:batch_update) do |_updates|
      LpAnalytics::Sheets::Client::Result.new(total_updated_rows: 0, total_updated_cells: 0)
    end

    assert_raises LpAnalytics::Sheets::IdempotentWriter::UpdateCountMismatchError do
      writer(client).call(rows: [ build_row(key: "a") ], aggregation_date: TARGET_DATE, exported_at: EXPORTED_AT)
    end
  end

  private

  def writer(client)
    LpAnalytics::Sheets::IdempotentWriter.new(client: client, worksheet_name: "daily_raw")
  end

  def build_row(key:, aggregation_date: TARGET_DATE, traffic_source: "", visit_count: 1)
    LpAnalytics::DailyAggregationQuery::Row.new(
      aggregation_key: key,
      aggregation_date: aggregation_date,
      lp_identifier: LpAnalytics::Configuration::STORE_LP_202607,
      traffic_source: traffic_source,
      utm_source: "",
      utm_medium: "",
      utm_campaign: "",
      utm_content: "",
      visit_count: visit_count,
      scroll_25_visit_count: 0,
      scroll_50_visit_count: 0,
      scroll_75_visit_count: 0,
      scroll_90_visit_count: 0,
      registration_cta_click_visit_count: 0,
      registration_cta_click_count: 0,
      registration_form_visit_count: 0,
      registration_completion_count: 0,
      registration_completion_visit_count: 0,
      registration_cv_rate: 0.0,
      contact_cta_click_visit_count: 0,
      contact_form_visit_count: 0,
      contact_completion_count: 0,
      contact_completion_visit_count: 0,
      contact_cv_rate: 0.0
    )
  end

  def sheet_values(row)
    [
      row.aggregation_key,
      row.aggregation_date.iso8601,
      row.lp_identifier,
      row.traffic_source,
      row.utm_source,
      row.utm_medium,
      row.utm_campaign,
      row.utm_content,
      row.visit_count,
      row.scroll_25_visit_count,
      row.scroll_50_visit_count,
      row.scroll_75_visit_count,
      row.scroll_90_visit_count,
      row.registration_cta_click_visit_count,
      row.registration_cta_click_count,
      row.registration_form_visit_count,
      row.registration_completion_count,
      row.registration_completion_visit_count,
      row.registration_cv_rate,
      row.contact_cta_click_visit_count,
      row.contact_form_visit_count,
      row.contact_completion_count,
      row.contact_completion_visit_count,
      row.contact_cv_rate,
      EXPORTED_AT.iso8601(6)
    ]
  end
end
