# frozen_string_literal: true

require "test_helper"

class StagingSafetyCheckTest < ActiveSupport::TestCase
  SAFE_ENV = {
    "APP_ENV" => "staging",
    "DATABASE_URL" => "postgresql://example.invalid/butterfly_room_staging",
    "AWS_S3_BUCKET" => "butterfly-room-staging",
    "STRIPE_SECRET_KEY" => "sk_test_example",
    "SMS_DELIVERY_MODE" => "mock",
    "IVS_STAGE_ENV" => "staging",
    "IVS_STAGE_NAME_PREFIX" => "br-staging",
    "GTM_ENABLED" => "false",
    "MAIL_DELIVERY_ENABLED" => "true",
    "MAIL_DELIVERY_MODE" => "redirect",
    "MAIL_REDIRECT_RECIPIENT" => "staging-mail@example.com",
    "BASIC_AUTH_ENABLED" => "true",
    "BASIC_AUTH_USERNAME" => "staging-user",
    "BASIC_AUTH_PASSWORD" => "example-password"
  }.freeze

  test "accepts a safe staging configuration" do
    assert_nil Staging::SafetyCheck.call!(env: SAFE_ENV)
  end

  test "accepts disabled Basic authentication without credentials" do
    env = SAFE_ENV.merge(
      "BASIC_AUTH_ENABLED" => "false",
      "BASIC_AUTH_USERNAME" => "",
      "BASIC_AUTH_PASSWORD" => ""
    )

    assert_nil Staging::SafetyCheck.call!(env: env)
  end

  test "does not change production behavior" do
    assert_nil Staging::SafetyCheck.call!(env: { "APP_ENV" => "production" })
  end

  test "rejects production database and storage" do
    assert_rejected("DATABASE_URL", "postgresql://example.invalid/butterfly_room_production")
    assert_rejected("AWS_S3_BUCKET", "butterfly-room-production")
  end

  test "rejects live Stripe and SMS settings" do
    assert_rejected("STRIPE_SECRET_KEY", "sk_live_example")
    assert_rejected("SMS_DELIVERY_MODE", "live")
  end

  test "requires explicit Stripe test and SMS mock settings" do
    assert_rejected("STRIPE_SECRET_KEY", "")
    assert_rejected("SMS_DELIVERY_MODE", "")
  end

  test "rejects non-staging IVS settings" do
    assert_rejected("IVS_STAGE_ENV", "production")
    assert_rejected("IVS_STAGE_NAME_PREFIX", "br")
  end

  test "rejects production GTM when staging tracking is enabled" do
    env = SAFE_ENV.merge(
      "GTM_ENABLED" => "true",
      "GTM_CONTAINER_ID" => Staging::SafetyCheck::PRODUCTION_GTM_CONTAINER_ID
    )

    assert_raises(Staging::SafetyCheck::ConfigurationError) do
      Staging::SafetyCheck.call!(env: env)
    end
  end

  test "rejects unrestricted or incomplete mail configuration" do
    assert_rejected("MAIL_DELIVERY_MODE", "live")
    assert_rejected("MAIL_REDIRECT_RECIPIENT", "")

    env = SAFE_ENV.merge("MAIL_DELIVERY_MODE" => "allowlist", "MAIL_ALLOWED_RECIPIENTS" => "")
    assert_raises(Staging::SafetyCheck::ConfigurationError) do
      Staging::SafetyCheck.call!(env: env)
    end
  end

  test "rejects missing Basic authentication credentials" do
    assert_rejected("BASIC_AUTH_PASSWORD", "")
  end

  private

  def assert_rejected(name, value)
    assert_raises(Staging::SafetyCheck::ConfigurationError) do
      Staging::SafetyCheck.call!(env: SAFE_ENV.merge(name => value))
    end
  end
end
