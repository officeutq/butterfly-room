# frozen_string_literal: true

module LpAnalytics
  class SheetExport < ApplicationRecord
    self.table_name = "lp_analytics_sheet_exports"

    enum :status, { pending: 0, running: 1, succeeded: 2, failed: 3 }

    validates :aggregation_date, :lp_identifier, :destination_fingerprint, :worksheet_name, presence: true
    validates :lp_identifier, :worksheet_name, length: { maximum: 100 }
    validates :destination_fingerprint, :payload_checksum,
      format: { with: /\A[0-9a-f]{64}\z/ },
      allow_nil: true
    validates :attempt_count, :row_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :error_class, length: { maximum: 200 }, allow_nil: true
    validates :error_message, length: { maximum: 500 }, allow_nil: true
  end
end
