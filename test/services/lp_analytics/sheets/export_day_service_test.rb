# frozen_string_literal: true

require "test_helper"

class LpAnalytics::Sheets::ExportDayServiceTest < ActiveSupport::TestCase
  TARGET_DATE = Date.new(2026, 8, 9)
  NOW = Time.zone.parse("2026-08-10 02:20:00")

  FakeApiError = Class.new(StandardError) do
    attr_reader :status_code

    def initialize(status_code, message = "sensitive response body")
      @status_code = status_code
      super(message)
    end
  end

  test "API通信中にtransactionを保持せず成功状態・行数・checksumを記録する" do
    transaction_states = []
    initial_open_transactions = ApplicationRecord.connection.open_transactions
    service = build_service(
      rows: [ build_row ],
      writer_action: ->(**) {
        transaction_states << ApplicationRecord.connection.open_transactions
        writer_result(row_count: 1)
      }
    )

    result = service.call
    export = result.export.reload

    assert_equal [ initial_open_transactions ], transaction_states
    assert export.succeeded?
    assert_equal 1, export.attempt_count
    assert_equal 1, export.row_count
    assert_match(/\A[0-9a-f]{64}\z/, export.payload_checksum)
    assert_equal NOW, export.completed_at
    assert_nil export.failed_at
    refute export.needs_retry?
  end

  test "同じ対象を再実行しても状態行を増やさずattemptを加算する" do
    service = build_service(rows: [ build_row ], writer_action: ->(**) { writer_result(row_count: 1) })

    assert_difference "LpAnalytics::SheetExport.count", 1 do
      service.call
      service.call
    end

    export = LpAnalytics::SheetExport.last
    assert export.succeeded?
    assert_equal 2, export.attempt_count
  end

  test "一時的なAPI最終失敗をneeds_retryとして秘密値なしで記録する" do
    log_output = StringIO.new
    logger = Logger.new(log_output)
    error = FakeApiError.new(503, "private-key and dummy-spreadsheet-id")
    service = build_service(rows: [ build_row ], writer_action: ->(**) { raise error }, logger: logger)

    assert_raises(FakeApiError) { service.call }
    export = LpAnalytics::SheetExport.last

    assert export.failed?
    assert export.needs_retry?
    assert_equal "external API request failed with status 503", export.error_message
    assert_equal FakeApiError.name, export.error_class
    assert_equal NOW, export.failed_at
    refute_includes export.error_message, "private-key"
    refute_includes log_output.string, "dummy-spreadsheet-id"
    refute_includes log_output.string, "dummy-secret-id"
  end

  test "403は再試行不要の失敗として記録する" do
    service = build_service(
      rows: [ build_row ],
      writer_action: ->(**) { raise FakeApiError.new(403) }
    )

    assert_raises(FakeApiError) { service.call }

    export = LpAnalytics::SheetExport.last
    assert export.failed?
    refute export.needs_retry?
  end

  test "同じ出力が実行中なら二重実行しない" do
    settings = valid_settings
    export = LpAnalytics::SheetExport.create!(
      aggregation_date: TARGET_DATE,
      lp_identifier: LpAnalytics::Configuration::STORE_LP_202607,
      destination_fingerprint: settings.destination_fingerprint,
      worksheet_name: settings.worksheet_name,
      status: :running,
      attempt_count: 1,
      row_count: 0,
      started_at: NOW - 5.minutes
    )
    service = build_service(
      rows: [ build_row ],
      writer_action: ->(**) { flunk "writer must not be called" },
      settings: settings
    )

    assert_raises(LpAnalytics::Sheets::ExportDayService::ExportAlreadyRunningError) { service.call }

    assert export.reload.running?
    assert_equal 1, export.attempt_count
  end

  private

  def build_service(rows:, writer_action:, logger: Logger.new(File::NULL), settings: valid_settings)
    query_class = Class.new do
      define_method(:initialize) { |**| }
      define_method(:call) { rows }
    end
    client_factory = Object.new
    client_factory.define_singleton_method(:call) { |_settings| Object.new }
    writer_class = Class.new do
      define_method(:initialize) { |**| }
      define_method(:call) { |**arguments| writer_action.call(**arguments) }
    end

    LpAnalytics::Sheets::ExportDayService.new(
      aggregation_date: TARGET_DATE,
      settings: settings,
      query_class: query_class,
      client_factory: client_factory,
      writer_class: writer_class,
      now: -> { NOW },
      logger: logger
    )
  end

  def valid_settings
    LpAnalytics::Sheets::Settings.new(
      enabled: true,
      region: "ap-northeast-1",
      spreadsheet_id: "dummy-spreadsheet-id",
      worksheet_name: "daily_raw",
      credentials_secret_id: "dummy-secret-id",
      rails_environment: "production"
    )
  end

  def writer_result(row_count:)
    LpAnalytics::Sheets::IdempotentWriter::Result.new(
      row_count: row_count,
      updated_sheet_row_count: row_count,
      updated_cell_count: row_count * LpAnalytics::Sheets::IdempotentWriter::HEADERS.length
    )
  end

  def build_row
    LpAnalytics::DailyAggregationQuery::Row.new(
      aggregation_key: "a" * 64,
      aggregation_date: TARGET_DATE,
      lp_identifier: LpAnalytics::Configuration::STORE_LP_202607,
      traffic_source: "meta",
      utm_source: "facebook",
      utm_medium: "paid_social",
      utm_campaign: "campaign_a",
      utm_content: "creative_a",
      device_type: "pc",
      visit_count: 1,
      scroll_25_visit_count: 1,
      scroll_50_visit_count: 0,
      scroll_75_visit_count: 0,
      scroll_90_visit_count: 0,
      section_usage_visit_count: 1,
      section_usage_rate: 1.0,
      section_strengths_visit_count: 0,
      section_strengths_rate: 0.0,
      section_system_visit_count: 0,
      section_system_rate: 0.0,
      section_pricing_visit_count: 0,
      section_pricing_rate: 0.0,
      section_flow_visit_count: 0,
      section_flow_rate: 0.0,
      section_cast_visit_count: 0,
      section_cast_rate: 0.0,
      section_qa_visit_count: 0,
      section_qa_rate: 0.0,
      section_bottom_cta_visit_count: 0,
      section_bottom_cta_rate: 0.0,
      section_existing_customer_opportunity_visit_count: 0,
      section_existing_customer_opportunity_rate: 0.0,
      section_service_introduction_visit_count: 0,
      section_service_introduction_rate: 0.0,
      section_usage_mechanism_visit_count: 0,
      section_usage_mechanism_rate: 0.0,
      section_service_comparison_visit_count: 0,
      section_service_comparison_rate: 0.0,
      section_adoption_cost_visit_count: 0,
      section_adoption_cost_rate: 0.0,
      section_usage_scenes_visit_count: 0,
      section_usage_scenes_rate: 0.0,
      section_getting_started_visit_count: 0,
      section_getting_started_rate: 0.0,
      section_final_opportunity_cta_visit_count: 0,
      section_final_opportunity_cta_rate: 0.0,
      registration_cta_click_visit_count: 1,
      registration_cta_click_count: 2,
      registration_form_visit_count: 1,
      registration_completion_count: 1,
      registration_completion_visit_count: 1,
      registration_cv_rate: 1.0,
      contact_cta_click_visit_count: 0,
      contact_form_visit_count: 0,
      contact_completion_count: 0,
      contact_completion_visit_count: 0,
      contact_cv_rate: 0.0
    )
  end
end
