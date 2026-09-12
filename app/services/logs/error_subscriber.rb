# frozen_string_literal: true

module Logs
  class ErrorSubscriber
    def report(error, handled:, severity:, context:, source: nil)
      return if ActionDispatch::ExceptionWrapper.status_code_for_exception(error.class.name) < 500

      normalized_source = case source.to_s
      when "application.action_dispatch" then "web"
      when "application.active_job" then "job"
      when "application.runner.railties" then "runner"
      else context[:log_source] || source
      end
      job = context[:job]
      if normalized_source == "job" && job.is_a?(ActiveJob::Base)
        context = context.merge(self.class.job_context(job))
      end
      RecordErrorService.call(error:, handled:, severity:, context:, source: normalized_source)
    end

    def self.job_context(job)
      {
        actor_user_id: nil, request_id: nil, store_id: nil, stream_session_id: nil,
        log_source: "job", job_class: job.class.name, job_id: job.job_id, executions: job.executions
      }
    end

    def self.report_job(event_name, payload)
      error = payload[:exception_object] || payload[:error]
      job = payload[:job]
      return unless error.is_a?(StandardError) && job.is_a?(ActiveJob::Base)

      handled = event_name != "perform.active_job"
      Rails.error.report(error, handled:, severity: :error, source: "job", context: job_context(job))
    end
  end
end
