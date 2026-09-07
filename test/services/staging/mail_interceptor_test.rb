# frozen_string_literal: true

require "test_helper"

class StagingMailInterceptorTest < ActiveSupport::TestCase
  test "direct mail preserves recipients and content while prefixing the subject" do
    message = Mail.new(
      to: "to@example.com",
      cc: "cc@example.com",
      bcc: "bcc@example.com",
      subject: "Notification",
      body: "Original content"
    )
    interceptor = Staging::MailInterceptor.new(env: {
      "APP_ENV" => "staging",
      "MAIL_DELIVERY_MODE" => "direct",
      "MAIL_REDIRECT_RECIPIENT" => "redirect@example.com",
      "MAIL_ALLOWED_RECIPIENTS" => "allowed@example.com",
      "MAIL_SUBJECT_PREFIX" => "[STAGING]"
    })

    2.times { interceptor.delivering_email(message) }

    assert_equal [ "to@example.com" ], message.to
    assert_equal [ "cc@example.com" ], message.cc
    assert_equal [ "bcc@example.com" ], message.bcc
    assert_equal "Original content", message.body.decoded
    assert_equal "[STAGING] Notification", message.subject
    assert_nil message.header["X-Staging-Original-To"]
    assert message.perform_deliveries
  end

  test "direct mail respects disabled delivery" do
    message = Mail.new(to: "recipient@example.com")
    interceptor = Staging::MailInterceptor.new(env: {
      "APP_ENV" => "staging",
      "MAIL_DELIVERY_MODE" => "direct",
      "MAIL_DELIVERY_ENABLED" => "false"
    })

    interceptor.delivering_email(message)

    assert_equal [ "recipient@example.com" ], message.to
    assert_not message.perform_deliveries
  end

  test "an unsupported mode suppresses delivery" do
    message = Mail.new(to: "recipient@example.com")

    Staging::MailInterceptor.new(env: {
      "APP_ENV" => "staging", "MAIL_DELIVERY_MODE" => "unknown"
    }).delivering_email(message)

    assert_not message.perform_deliveries
  end

  test "allowlist retains only allowed recipients across to cc and bcc" do
    message = Mail.new(
      to: [ "allowed@example.com", "other@example.com" ],
      cc: "allowed@example.com",
      bcc: "other@example.com"
    )
    Staging::MailInterceptor.new(env: {
      "APP_ENV" => "staging",
      "MAIL_DELIVERY_MODE" => "allowlist",
      "MAIL_ALLOWED_RECIPIENTS" => "ALLOWED@example.com"
    }).delivering_email(message)

    assert_equal [ "allowed@example.com" ], message.to
    assert_equal [ "allowed@example.com" ], message.cc
    assert_empty Array(message.bcc)
    assert message.perform_deliveries
  end

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
