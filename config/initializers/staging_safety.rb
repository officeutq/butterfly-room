# frozen_string_literal: true

Rails.application.config.after_initialize do
  Staging::SafetyCheck.call!
  ActionMailer::Base.register_interceptor(Staging::MailInterceptor)
end
