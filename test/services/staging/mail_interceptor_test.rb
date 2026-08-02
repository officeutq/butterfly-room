# frozen_string_literal: true

require "test_helper"

class StagingMailInterceptorTest < ActiveSupport::TestCase
  test "redirects every recipient and records the originals" do
    message = Mail.new(
      to: "to@example.com",
      cc: "cc@example.com",
      bcc: "bcc@example.com",
      subject: "Notification"
    )
    interceptor = Staging::MailInterceptor.new(env: {
      "APP_ENV" => "staging",
      "MAIL_DELIVERY_ENABLED" => "true",
      "MAIL_DELIVERY_MODE" => "redirect",
      "MAIL_REDIRECT_RECIPIENT" => "safe@example.com",
      "MAIL_SUBJECT_PREFIX" => "[STAGING]"
    })

    interceptor.delivering_email(message)

    assert_equal [ "safe@example.com" ], message.to
    assert_nil message.cc
    assert_nil message.bcc
    assert_equal "to@example.com", message.header["X-Staging-Original-To"].value
    assert_equal "cc@example.com", message.header["X-Staging-Original-Cc"].value
    assert_equal "bcc@example.com", message.header["X-Staging-Original-Bcc"].value
    assert_equal "[STAGING] Notification", message.subject
    assert message.perform_deliveries
  end

  test "allowlist mode suppresses a message with no allowed recipient" do
    message = Mail.new(to: "production-user@example.com", subject: "Notification")
    interceptor = Staging::MailInterceptor.new(env: {
      "APP_ENV" => "staging",
      "MAIL_DELIVERY_ENABLED" => "true",
      "MAIL_DELIVERY_MODE" => "allowlist",
      "MAIL_ALLOWED_RECIPIENTS" => "tester@example.com"
    })

    interceptor.delivering_email(message)

    assert_empty Array(message.to)
    assert_not message.perform_deliveries
  end

  test "production mail remains unchanged" do
    message = Mail.new(to: "recipient@example.com", subject: "Notification")

    Staging::MailInterceptor.new(env: { "APP_ENV" => "production" }).delivering_email(message)

    assert_equal [ "recipient@example.com" ], message.to
    assert_equal "Notification", message.subject
    assert message.perform_deliveries
  end
end
