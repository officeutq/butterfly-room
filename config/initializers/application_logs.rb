# frozen_string_literal: true

Rails.application.config.to_prepare do
  previous = Rails.application.config.x.application_log_subscriber
  Rails.error.unsubscribe(previous) if previous
  subscriber = Logs::ErrorSubscriber.new
  Rails.application.config.x.application_log_subscriber = subscriber
  Rails.error.subscribe(subscriber)
end

# All ActiveJob subclasses, including ActionMailer::MailDeliveryJob. Notifications
# also cover argument deserialization and handled retry/discard failures.
%w[perform enqueue_retry discard].each do |operation|
  ActiveSupport::Notifications.subscribe("#{operation}.active_job") do |name, _start, _finish, _id, payload|
    Logs::ErrorSubscriber.report_job(name, payload)
  end
end

ActiveSupport.on_load(:active_job) do
  around_perform do |job, block|
    ActiveSupport::ExecutionContext.set(**Logs::ErrorSubscriber.job_context(job)) { block.call }
  end
end
