# frozen_string_literal: true

class CreateLpAnalyticsSheetExports < ActiveRecord::Migration[8.1]
  def change
    create_table :lp_analytics_sheet_exports do |t|
      t.date :aggregation_date, null: false
      t.string :lp_identifier, null: false, limit: 100
      t.string :destination_fingerprint, null: false, limit: 64
      t.string :worksheet_name, null: false, limit: 100
      t.integer :status, null: false, default: 0
      t.integer :attempt_count, null: false, default: 0
      t.integer :row_count, null: false, default: 0
      t.string :payload_checksum, limit: 64
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :failed_at
      t.string :error_class, limit: 200
      t.string :error_message, limit: 500
      t.boolean :needs_retry, null: false, default: false
      t.timestamps
    end

    add_index :lp_analytics_sheet_exports,
      %i[aggregation_date lp_identifier destination_fingerprint worksheet_name],
      unique: true,
      name: "uniq_lp_analytics_sheet_exports_target"
    add_index :lp_analytics_sheet_exports, %i[status needs_retry]
  end
end
