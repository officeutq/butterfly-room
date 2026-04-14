# frozen_string_literal: true

module Sms
  class Sender
    class Error < StandardError; end
    class DeliveryNotAllowed < Error; end
    class ConfigurationError < Error; end

    def initialize(client: Sms::Client.build, logger: Rails.logger)
      @client = client
      @logger = logger
    end

    def deliver!(phone_number:, message:)
      raise ConfigurationError, "phone_number is blank" if phone_number.blank?
      raise ConfigurationError, "message is blank" if message.blank?

      case delivery_mode
      when "live"
        @client.publish!(phone_number: phone_number, message: message)
      when "allowlist"
        ensure_allowed_number!(phone_number)
        @client.publish!(phone_number: phone_number, message: message)
      else
        log_mock_delivery(phone_number:, message:)
        nil
      end
    end

    private

    def delivery_mode
      ENV["SMS_DELIVERY_MODE"].presence ||
        Rails.application.credentials.dig(:sms, :delivery_mode).presence ||
        default_delivery_mode
    end

    def default_delivery_mode
      if Rails.env.production?
        "live"
      else
        "mock"
      end
    end

    def allowed_test_numbers
      raw =
        ENV["SMS_ALLOWED_TEST_NUMBERS"].presence ||
        Array(Rails.application.credentials.dig(:sms, :allowed_test_numbers)).join(",")

      raw.to_s.split(",").map(&:strip).reject(&:blank?)
    end

    def ensure_allowed_number!(phone_number)
      return if allowed_test_numbers.include?(phone_number)

      raise DeliveryNotAllowed, "phone_number is not included in SMS_ALLOWED_TEST_NUMBERS"
    end

    def log_mock_delivery(phone_number:, message:)
      @logger.info("[SMS MOCK] to=#{phone_number} message=#{message}")
    end
  end
end
