# frozen_string_literal: true

require "test_helper"

class LpAnalytics::SheetExportTest < ActiveSupport::TestCase
  test "出力状態の初期値と非秘密な出力先識別情報を保持する" do
    export = LpAnalytics::SheetExport.create!(
      aggregation_date: Date.new(2026, 8, 9),
      lp_identifier: LpAnalytics::Configuration::STORE_LP_202607,
      destination_fingerprint: "a" * 64,
      worksheet_name: "daily_raw"
    )

    assert export.pending?
    assert_equal 0, export.attempt_count
    assert_equal 0, export.row_count
    refute export.needs_retry?
  end

  test "Secret値・Spreadsheet ID・個人情報の列を持たない" do
    forbidden_columns = %w[
      spreadsheet_id
      credentials_secret_id
      credentials_json
      private_key
      access_token
      name
      email
      phone_number
      form_payload
    ]

    forbidden_columns.each do |column|
      refute_includes LpAnalytics::SheetExport.column_names, column
    end
  end
end
