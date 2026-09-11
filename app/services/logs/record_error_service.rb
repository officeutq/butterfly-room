# frozen_string_literal: true

module Logs
  class RecordErrorService
    GUARD_KEY = :application_error_log_writing
    SUMMARY = "処理中にエラーが発生しました。例外クラス・発生箇所・関連IDで確認してください。"

    def self.call(error:, handled: false, severity: :error, source: "application", context: {}, logger: Rails.logger)
      return if ActiveSupport::IsolatedExecutionState[GUARD_KEY]

      begin
        ActiveSupport::IsolatedExecutionState[GUARD_KEY] = true
        context = context.to_h.symbolize_keys
        attributes = {
          occurred_at: Time.current, handled:, severity: severity.to_s,
          exception_class: Sanitizer.class_name(error.class.name) || "Exception",
          summary: SUMMARY, backtrace: Sanitizer.backtrace(error),
          source: LogEntry::SOURCES.include?(source.to_s) ? source.to_s : "application",
          request_id: Sanitizer.identifier(context[:request_id]),
          actor_user_id: Sanitizer.positive_id(context[:actor_user_id]),
          store_id: Sanitizer.positive_id(context[:store_id]),
          stream_session_id: Sanitizer.positive_id(context[:stream_session_id]),
          job_class: Sanitizer.class_name(context[:job_class]),
          job_id: Sanitizer.identifier(context[:job_id]),
          executions: Sanitizer.positive_id(context[:executions])
        }
        ErrorLog.connection_pool.with_connection { ErrorLog.create!(attributes) }
      rescue StandardError => storage_error
        # Never interpolate exception messages, request parameters, job arguments or URLs.
        begin
          logger.error({ event: "error_log_write_failed", exception_class: Sanitizer.class_name(error.class.name), storage_error_class: Sanitizer.class_name(storage_error.class.name), request_id: attributes&.dig(:request_id) }.to_json)
        rescue StandardError
          nil
        end
        nil
      ensure
        ActiveSupport::IsolatedExecutionState.delete(GUARD_KEY)
      end
    end
  end
end
