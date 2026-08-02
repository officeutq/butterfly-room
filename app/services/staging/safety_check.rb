# frozen_string_literal: true

module Staging
  class SafetyCheck
    class ConfigurationError < StandardError; end

    PRODUCTION_DATABASE_NAME = "butterfly_room_production"
    PRODUCTION_S3_BUCKET = "butterfly-room-production"
    PRODUCTION_GTM_CONTAINER_ID = "GTM-KNT7H4CG"
    SAFE_MAIL_MODES = %w[redirect allowlist].freeze

    def self.call!(env: ENV)
      new(env: env).call!
    end

    def initialize(env: ENV)
      @env = env
    end

    def call!
      return unless Runtime.staging?(@env)

      reject_production_database!
      reject_production_s3!
      reject_live_integrations!
      validate_ivs!
      validate_gtm!
      validate_mail!
      validate_basic_auth!
    end

    private

    def reject_production_database!
      return unless value("DATABASE_URL").include?(PRODUCTION_DATABASE_NAME)

      fail_configuration!("DATABASE_URL must not reference the production database")
    end

    def reject_production_s3!
      return unless value("AWS_S3_BUCKET") == PRODUCTION_S3_BUCKET

      fail_configuration!("AWS_S3_BUCKET must not reference the production bucket")
    end

    def reject_live_integrations!
      unless value("STRIPE_SECRET_KEY").start_with?("sk_test_")
        fail_configuration!("STRIPE_SECRET_KEY must use Stripe test mode")
      end

      unless value("SMS_DELIVERY_MODE") == "mock"
        fail_configuration!("SMS_DELIVERY_MODE must be mock")
      end
    end

    def validate_ivs!
      fail_configuration!("IVS_STAGE_ENV must be staging") unless value("IVS_STAGE_ENV") == "staging"
      return if value("IVS_STAGE_NAME_PREFIX") == "br-staging"

      fail_configuration!("IVS_STAGE_NAME_PREFIX must be br-staging")
    end

    def validate_gtm!
      return unless Runtime.gtm_enabled?(@env)
      return unless value("GTM_CONTAINER_ID").empty? || value("GTM_CONTAINER_ID") == PRODUCTION_GTM_CONTAINER_ID

      fail_configuration!("GTM must be disabled or use a non-production container in staging")
    end

    def validate_mail!
      return unless Runtime.enabled?("MAIL_DELIVERY_ENABLED", default: true, env: @env)

      mode = value("MAIL_DELIVERY_MODE")
      fail_configuration!("MAIL_DELIVERY_MODE must restrict staging recipients") unless SAFE_MAIL_MODES.include?(mode)

      if mode == "redirect" && value("MAIL_REDIRECT_RECIPIENT").empty?
        fail_configuration!("MAIL_REDIRECT_RECIPIENT is required in redirect mode")
      end

      if mode == "allowlist" && csv_values("MAIL_ALLOWED_RECIPIENTS").empty?
        fail_configuration!("MAIL_ALLOWED_RECIPIENTS is required in allowlist mode")
      end
    end

    def validate_basic_auth!
      return unless Runtime.enabled?("BASIC_AUTH_ENABLED", default: true, env: @env)
      return if value("BASIC_AUTH_USERNAME").present? && value("BASIC_AUTH_PASSWORD").present?

      fail_configuration!("Basic authentication credentials are required when enabled")
    end

    def csv_values(name)
      value(name).split(",").map(&:strip).reject(&:empty?)
    end

    def value(name)
      @env[name].to_s.strip
    end

    def fail_configuration!(message)
      raise ConfigurationError, "Staging safety check failed: #{message}"
    end
  end
end
