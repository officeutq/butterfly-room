# frozen_string_literal: true

require "timeout"
require "socket"

module LpAnalytics
  module Sheets
    class RetryPolicy
      DEFAULT_MAX_ATTEMPTS = 3
      DEFAULT_BASE_DELAY = 0.5
      TRANSIENT_ERROR_NAMES = %w[
        Google::Apis::RateLimitError
        Google::Apis::ServerError
        Google::Apis::TransmissionError
      ].freeze
      NETWORK_ERRORS = [
        Timeout::Error,
        EOFError,
        SocketError,
        Errno::ECONNRESET,
        Errno::ECONNREFUSED,
        Errno::EHOSTUNREACH,
        Errno::ETIMEDOUT
      ].freeze

      def initialize(max_attempts: DEFAULT_MAX_ATTEMPTS, base_delay: DEFAULT_BASE_DELAY, sleeper: Kernel.method(:sleep))
        @max_attempts = max_attempts
        @base_delay = base_delay
        @sleeper = sleeper
      end

      def call
        attempt = 0

        begin
          attempt += 1
          yield
        rescue StandardError => error
          raise unless self.class.transient?(error) && attempt < max_attempts

          sleeper.call(base_delay * (2**(attempt - 1)))
          retry
        end
      end

      def self.transient?(error)
        status = error_status(error)
        return true if status == 429 || status&.between?(500, 599)
        return true if TRANSIENT_ERROR_NAMES.include?(error.class.name)

        NETWORK_ERRORS.any? { |error_class| error.is_a?(error_class) }
      end

      def self.error_status(error)
        value = if error.respond_to?(:status_code)
          error.status_code
        elsif error.respond_to?(:status)
          error.status
        end
        Integer(value, exception: false)
      end
      private_class_method :error_status

      private

      attr_reader :max_attempts, :base_delay, :sleeper
    end
  end
end
