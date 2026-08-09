# frozen_string_literal: true

require "google/apis/sheets_v4"

module LpAnalytics
  module Sheets
    class Client
      Result = Data.define(:total_updated_rows, :total_updated_cells)

      def initialize(service:, spreadsheet_id:, retry_policy: RetryPolicy.new)
        @service = service
        @spreadsheet_id = spreadsheet_id
        @retry_policy = retry_policy
      end

      def read_values(range)
        response = retry_policy.call do
          service.get_spreadsheet_values(spreadsheet_id, range)
        end
        response.values || []
      end

      def batch_update(updates)
        request = Google::Apis::SheetsV4::BatchUpdateValuesRequest.new(
          value_input_option: "RAW",
          data: updates.map do |update|
            Google::Apis::SheetsV4::ValueRange.new(
              range: update.fetch(:range),
              major_dimension: "ROWS",
              values: update.fetch(:values)
            )
          end
        )
        response = retry_policy.call do
          service.batch_update_values(spreadsheet_id, request)
        end

        Result.new(
          total_updated_rows: response.total_updated_rows.to_i,
          total_updated_cells: response.total_updated_cells.to_i
        )
      end

      private

      attr_reader :service, :spreadsheet_id, :retry_policy
    end
  end
end
