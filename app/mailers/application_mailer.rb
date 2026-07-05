class ApplicationMailer < ActionMailer::Base
  DEFAULT_FROM_ENV_KEY = "MAILER_SENDER"
  DEFAULT_FROM = "no-reply@butterflyve.jp"

  default from: -> { ENV.fetch(DEFAULT_FROM_ENV_KEY, DEFAULT_FROM) }
  layout "mailer"
end
