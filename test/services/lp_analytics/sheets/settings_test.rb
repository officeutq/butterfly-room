# frozen_string_literal: true

require "test_helper"

class LpAnalytics::Sheets::SettingsTest < ActiveSupport::TestCase
  VALID_ENV = {
    "LP_ANALYTICS_SHEETS_EXPORT_ENABLED" => "true",
    "AWS_REGION" => "ap-northeast-1",
    "GOOGLE_SHEETS_SPREADSHEET_ID" => "dummy-spreadsheet-id",
    "GOOGLE_SHEETS_WORKSHEET_NAME" => "daily_raw",
    "GOOGLE_SHEETS_CREDENTIALS_SECRET_ID" => "dummy-secret-id"
  }.freeze

  test "自動出力はproductionかつflagがtrueの場合だけ有効にする" do
    production = LpAnalytics::Sheets::Settings.from_env(env: VALID_ENV, rails_environment: "production")
    staging = LpAnalytics::Sheets::Settings.from_env(
      env: VALID_ENV.merge("LP_ANALYTICS_SHEETS_EXPORT_ENABLED" => "false"),
      rails_environment: "production"
    )
    test_environment = LpAnalytics::Sheets::Settings.from_env(env: VALID_ENV, rails_environment: "test")

    assert production.automatic_export_enabled?
    refute staging.automatic_export_enabled?
    refute test_environment.automatic_export_enabled?
  end

  test "必須設定不足を値を含めずに拒否する" do
    settings = LpAnalytics::Sheets::Settings.from_env(
      env: VALID_ENV.merge("GOOGLE_SHEETS_SPREADSHEET_ID" => ""),
      rails_environment: "production"
    )

    error = assert_raises(LpAnalytics::Sheets::Settings::ConfigurationError) { settings.validate! }

    assert_includes error.message, "GOOGLE_SHEETS_SPREADSHEET_ID"
    refute_includes error.message, VALID_ENV.fetch("GOOGLE_SHEETS_CREDENTIALS_SECRET_ID")
  end

  test "出力先fingerprintへ実IDを含めない" do
    settings = LpAnalytics::Sheets::Settings.from_env(env: VALID_ENV, rails_environment: "production")

    assert_match(/\A[0-9a-f]{64}\z/, settings.destination_fingerprint)
    refute_includes settings.destination_fingerprint, VALID_ENV.fetch("GOOGLE_SHEETS_SPREADSHEET_ID")
  end

  test "環境別Spreadsheetから異なる出力先fingerprintを生成する" do
    production = LpAnalytics::Sheets::Settings.from_env(env: VALID_ENV, rails_environment: "production")
    staging = LpAnalytics::Sheets::Settings.from_env(
      env: VALID_ENV.merge(
        "LP_ANALYTICS_SHEETS_EXPORT_ENABLED" => "false",
        "GOOGLE_SHEETS_SPREADSHEET_ID" => "staging-dummy-spreadsheet",
        "GOOGLE_SHEETS_CREDENTIALS_SECRET_ID" => "staging-dummy-secret"
      ),
      rails_environment: "production"
    )

    refute_equal production.destination_fingerprint, staging.destination_fingerprint
    refute staging.automatic_export_enabled?
  end
end
