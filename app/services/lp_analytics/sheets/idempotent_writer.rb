# frozen_string_literal: true

require "set"

module LpAnalytics
  module Sheets
    class IdempotentWriter
      class HeaderMismatchError < StandardError; end
      class DuplicateAggregationKeyError < StandardError; end
      class SheetStructureError < StandardError; end
      class UpdateCountMismatchError < StandardError; end

      LEGACY_HEADERS = %w[
        aggregation_key
        aggregation_date
        lp_identifier
        traffic_source
        utm_source
        utm_medium
        utm_campaign
        utm_content
        lp_visit_count
        scroll_25_visit_count
        scroll_50_visit_count
        scroll_75_visit_count
        scroll_90_visit_count
        registration_cta_click_visit_count
        registration_cta_click_count
        registration_form_visit_count
        registration_completion_count
        registration_completion_visit_count
        registration_cv_rate
        contact_cta_click_visit_count
        contact_form_visit_count
        contact_completion_count
        contact_completion_visit_count
        contact_cv_rate
        exported_at
      ].freeze

      HEADERS = %w[
        aggregation_key
        aggregation_date
        lp_identifier
        traffic_source
        utm_source
        utm_medium
        utm_campaign
        utm_content
        device_type
        lp_visit_count
        scroll_25_visit_count
        scroll_50_visit_count
        scroll_75_visit_count
        scroll_90_visit_count
        section_usage_visit_count
        section_usage_rate
        section_strengths_visit_count
        section_strengths_rate
        section_system_visit_count
        section_system_rate
        section_pricing_visit_count
        section_pricing_rate
        section_flow_visit_count
        section_flow_rate
        section_cast_visit_count
        section_cast_rate
        section_qa_visit_count
        section_qa_rate
        section_bottom_cta_visit_count
        section_bottom_cta_rate
        registration_cta_click_visit_count
        registration_cta_click_count
        registration_form_visit_count
        registration_completion_count
        registration_completion_visit_count
        registration_cv_rate
        contact_cta_click_visit_count
        contact_form_visit_count
        contact_completion_count
        contact_completion_visit_count
        contact_cv_rate
        exported_at
      ].freeze

      Result = Data.define(:row_count, :updated_sheet_row_count, :updated_cell_count)
      ExistingRow = Data.define(:row_number, :aggregation_key, :aggregation_date, :values)

      def initialize(client:, worksheet_name:)
        @client = client
        @worksheet_name = worksheet_name
      end

      def call(rows:, aggregation_date:, exported_at: Time.zone.now)
        date = strict_date(aggregation_date)
        validate_rows!(rows, date)
        sheet_values = client.read_values(full_range)
        existing_rows, updates = inspect_sheet(sheet_values)
        updates.concat(build_row_updates(rows, existing_rows, sheet_values.length, date, exported_at))
        updates.concat(build_stale_row_updates(rows, existing_rows, date))
        updates = collapse_updates(updates)

        response = updates.empty? ? nil : client.batch_update(updates)
        validate_response!(response, updates)

        Result.new(
          row_count: rows.length,
          updated_sheet_row_count: response&.total_updated_rows.to_i,
          updated_cell_count: response&.total_updated_cells.to_i
        )
      end

      private

      attr_reader :client, :worksheet_name

      def inspect_sheet(sheet_values)
        if sheet_values.empty?
          return [ [], [ update_for(row_number: 1, values: HEADERS) ] ]
        end

        header = Array(sheet_values.first).map(&:to_s)
        unless [ HEADERS, LEGACY_HEADERS ].include?(header)
          raise HeaderMismatchError, "worksheet header does not match"
        end

        rows = inspect_managed_rows(sheet_values.drop(1), headers: header)
        return [ rows, [] ] if header == HEADERS

        migrated_rows = rows.map do |row|
          legacy_values = LEGACY_HEADERS.zip(row.values).to_h
          values = HEADERS.map { |column| legacy_values.fetch(column, "") }
          ExistingRow.new(
            row_number: row.row_number,
            aggregation_key: row.aggregation_key,
            aggregation_date: row.aggregation_date,
            values: values
          )
        end
        updates = [ update_for(row_number: 1, values: HEADERS) ]
        updates.concat(
          migrated_rows.map do |row|
            update_for(row_number: row.row_number, values: row.values)
          end
        )

        [ migrated_rows, updates ]
      end

      def inspect_managed_rows(sheet_rows, headers:)
        seen_keys = {}
        Array(sheet_rows).each_with_index.filter_map do |values, index|
          row_number = index + 2
          normalized = Array(values).map(&:to_s)
          next if normalized.all?(&:blank?)

          key = normalized.fetch(0, "")
          date = normalized.fetch(1, "")
          if normalized.length != headers.length || key.blank? || date.blank?
            raise SheetStructureError, "worksheet contains a partial managed row"
          end
          raise DuplicateAggregationKeyError, "worksheet contains duplicate aggregation keys" if seen_keys.key?(key)

          seen_keys[key] = row_number
          ExistingRow.new(row_number: row_number, aggregation_key: key, aggregation_date: date, values: normalized)
        end
      end

      def build_row_updates(rows, existing_rows, existing_sheet_length, date, exported_at)
        by_key = existing_rows.index_by(&:aggregation_key)
        empty_row_numbers = empty_row_numbers(existing_rows, existing_sheet_length)
        next_row_number = [ existing_sheet_length + 1, 2 ].max

        rows.sort_by(&:aggregation_key).map do |row|
          existing = by_key[row.aggregation_key]
          if existing && existing.aggregation_date != date.iso8601
            raise SheetStructureError, "aggregation key is associated with a different date"
          end
          row_number = existing&.row_number || empty_row_numbers.shift || next_row_number.tap { next_row_number += 1 }
          update_for(row_number: row_number, values: sheet_row_values(row, date, exported_at))
        end
      end

      def build_stale_row_updates(rows, existing_rows, date)
        current_keys = rows.to_set(&:aggregation_key)
        existing_rows.filter_map do |existing|
          next unless existing.aggregation_date == date.iso8601
          next if current_keys.include?(existing.aggregation_key)

          update_for(row_number: existing.row_number, values: Array.new(HEADERS.length, ""))
        end
      end

      def empty_row_numbers(existing_rows, existing_sheet_length)
        occupied = existing_rows.to_set(&:row_number)
        (2..existing_sheet_length).reject { |row_number| occupied.include?(row_number) }
      end

      def sheet_row_values(row, date, exported_at)
        [
          row.aggregation_key,
          date.iso8601,
          row.lp_identifier,
          row.traffic_source,
          row.utm_source,
          row.utm_medium,
          row.utm_campaign,
          row.utm_content,
          row.device_type,
          row.visit_count,
          row.scroll_25_visit_count,
          row.scroll_50_visit_count,
          row.scroll_75_visit_count,
          row.scroll_90_visit_count,
          row.section_usage_visit_count,
          row.section_usage_rate,
          row.section_strengths_visit_count,
          row.section_strengths_rate,
          row.section_system_visit_count,
          row.section_system_rate,
          row.section_pricing_visit_count,
          row.section_pricing_rate,
          row.section_flow_visit_count,
          row.section_flow_rate,
          row.section_cast_visit_count,
          row.section_cast_rate,
          row.section_qa_visit_count,
          row.section_qa_rate,
          row.section_bottom_cta_visit_count,
          row.section_bottom_cta_rate,
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
          exported_at.iso8601(6)
        ]
      end

      def collapse_updates(updates)
        updates.each_with_object({}) do |update, by_range|
          by_range[update.fetch(:range)] = update
        end.values
      end

      def update_for(row_number:, values:)
        {
          range: "#{quoted_worksheet_name}!A#{row_number}:#{last_column}#{row_number}",
          values: [ values ]
        }
      end

      def full_range
        "#{quoted_worksheet_name}!A:#{last_column}"
      end

      def quoted_worksheet_name
        "'#{worksheet_name.gsub("'", "''")}'"
      end

      def last_column
        number = HEADERS.length
        result = +""
        while number.positive?
          number -= 1
          result.prepend((65 + (number % 26)).chr)
          number /= 26
        end
        result
      end

      def validate_rows!(rows, date)
        keys = rows.map(&:aggregation_key)
        raise DuplicateAggregationKeyError, "payload contains duplicate aggregation keys" unless keys.uniq.length == keys.length
        raise ArgumentError, "payload contains a different aggregation date" unless rows.all? { |row| row.aggregation_date == date }
      end

      def validate_response!(response, updates)
        return if updates.empty?

        expected_rows = updates.length
        expected_cells = expected_rows * HEADERS.length
        return if response.total_updated_rows == expected_rows && response.total_updated_cells == expected_cells

        raise UpdateCountMismatchError, "Google Sheets updated count does not match the request"
      end

      def strict_date(value)
        return value if value.instance_of?(Date)

        raw = value.to_s
        raise Date::Error unless raw.match?(/\A\d{4}-\d{2}-\d{2}\z/)

        Date.iso8601(raw)
      rescue Date::Error
        raise ArgumentError, "aggregation date must be YYYY-MM-DD"
      end
    end
  end
end
