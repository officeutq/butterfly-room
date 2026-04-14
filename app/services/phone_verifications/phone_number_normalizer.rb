# frozen_string_literal: true

module PhoneVerifications
  class PhoneNumberNormalizer
    class InvalidPhoneNumber < StandardError; end

    def self.call(phone_number)
      new(phone_number).call
    end

    def initialize(phone_number)
      @phone_number = phone_number.to_s
    end

    def call
      normalized = @phone_number.gsub(/[^\d+]/, "")

      if normalized.start_with?("+")
        validate_e164!(normalized)
        return normalized
      end

      digits = normalized.gsub(/\D/, "")

      if digits.start_with?("0")
        digits = digits.sub(/\A0/, "81")
      end

      normalized = "+#{digits}"
      validate_e164!(normalized)
      normalized
    end

    private

    def validate_e164!(value)
      raise InvalidPhoneNumber, "phone_number is invalid" unless value.match?(/\A\+[1-9]\d{7,14}\z/)
    end
  end
end
