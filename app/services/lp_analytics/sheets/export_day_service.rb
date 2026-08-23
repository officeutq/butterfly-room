# frozen_string_literal: true

require "digest"
require "json"

module LpAnalytics
  module Sheets
    class ExportDayService
      class ExportAlreadyRunningError < StandardError; end

      STALE_RUNNING_AFTER = 1.hour
      Result = Data.define(:export, :row_count, :payload_checksum)

      def initialize(
        aggregation_date:,
        lp_identifier: Configuration::STORE_LP_202607,
        settings: Settings.from_env,
        query_class: DailyAggregationQuery,
        client_factory: ClientFactory.new,
        writer_class: IdempotentWriter,
        now: -> { Time.zone.now },
        logger: Rails.logger
      )
        @aggregation_date = strict_date(aggregation_date)
        @lp_identifier = lp_identifier
        @settings = settings
        @query_class = query_class
        @client_factory = client_factory
        @writer_class = writer_class
        @now = now
        @logger = logger
      end

      def call
        settings.validate!
        export = claim_export!
        claimed = true
        rows = query_class.new(aggregation_date: aggregation_date, lp_identifier: lp_identifier).call
        checksum = payload_checksum(rows)
        client = client_factory.call(settings)
        result = writer_class.new(client: client, worksheet_name: settings.worksheet_name).call(
          rows: rows,
          aggregation_date: aggregation_date,
          lp_identifier: lp_identifier,
          exported_at: now.call
        )
        completed_at = now.call
        export.update!(
          status: :succeeded,
          row_count: result.row_count,
          payload_checksum: checksum,
          completed_at: completed_at,
          failed_at: nil,
          error_class: nil,
          error_message: nil,
          needs_retry: false
        )
        log_success(export, result)

        Result.new(export: export, row_count: result.row_count, payload_checksum: checksum)
      rescue StandardError => error
        mark_failed(export, error) if claimed
        raise
      end

      private

      attr_reader :aggregation_date, :lp_identifier, :settings, :query_class, :client_factory,
        :writer_class, :now, :logger

      def claim_export!
        export = find_or_create_export
        current_time = now.call

        export.with_lock do
          if export.running? && export.started_at.present? && export.started_at >= current_time - STALE_RUNNING_AFTER
            raise ExportAlreadyRunningError, "export is already running"
          end

          export.update!(
            status: :running,
            attempt_count: export.attempt_count + 1,
            started_at: current_time,
            completed_at: nil,
            failed_at: nil,
            row_count: 0,
            payload_checksum: nil,
            error_class: nil,
            error_message: nil,
            needs_retry: false
          )
        end

        export
      end

      def find_or_create_export
        attributes = {
          aggregation_date: aggregation_date,
          lp_identifier: lp_identifier,
          destination_fingerprint: settings.destination_fingerprint,
          worksheet_name: settings.worksheet_name
        }

        SheetExport.create_or_find_by!(attributes) do |export|
          export.status = :pending
          export.attempt_count = 0
          export.row_count = 0
        end
      end

      def mark_failed(export, error)
        failed_at = now.call
        needs_retry = RetryPolicy.transient?(error)
        export.update!(
          status: :failed,
          failed_at: failed_at,
          completed_at: nil,
          error_class: error.class.name.to_s.first(200),
          error_message: safe_error_message(error),
          needs_retry: needs_retry
        )
        logger.error(
          "[LpAnalyticsSheetsExport] failed " \
          "aggregation_date=#{aggregation_date.iso8601} " \
          "lp_identifier=#{lp_identifier} " \
          "destination=#{settings.destination_fingerprint.first(12)} " \
          "error_class=#{error.class.name} needs_retry=#{needs_retry}"
        )
      end

      def log_success(export, result)
        logger.info(
          "[LpAnalyticsSheetsExport] succeeded " \
          "aggregation_date=#{aggregation_date.iso8601} " \
          "lp_identifier=#{lp_identifier} " \
          "destination=#{settings.destination_fingerprint.first(12)} " \
          "attempt_count=#{export.attempt_count} row_count=#{result.row_count}"
        )
      end

      def safe_error_message(error)
        case error
        when Settings::ConfigurationError
          "LP analytics Sheets configuration is missing or invalid"
        when CredentialsProvider::CredentialsError
          "service account credentials could not be loaded"
        when IdempotentWriter::HeaderMismatchError
          "managed worksheet header does not match the expected schema"
        when IdempotentWriter::DuplicateAggregationKeyError
          "managed worksheet contains duplicate aggregation keys"
        when IdempotentWriter::SheetStructureError
          "managed worksheet contains an invalid row"
        when IdempotentWriter::UpdateCountMismatchError
          "Google Sheets updated count does not match the request"
        when ExportAlreadyRunningError
          "the same export is already running"
        else
          status = error.respond_to?(:status_code) ? Integer(error.status_code, exception: false) : nil
          status ? "external API request failed with status #{status}" : "LP analytics Sheets export failed"
        end.first(500)
      end

      def payload_checksum(rows)
        payload = rows.sort_by(&:aggregation_key).map do |row|
          row.to_h.transform_values { |value| value.respond_to?(:iso8601) ? value.iso8601 : value }
        end
        Digest::SHA256.hexdigest(JSON.generate(payload))
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
