# frozen_string_literal: true

module Staging
  class Runtime
    TRUTHY_VALUES = %w[1 true yes on].freeze
    FALSY_VALUES = %w[0 false no off].freeze

    class << self
      def staging?(env = ENV)
        env["APP_ENV"] == "staging"
      end

      def enabled?(name, default:, env: ENV)
        value = env[name]
        return default if value.nil? || value.strip.empty?

        normalized = value.downcase
        return true if TRUTHY_VALUES.include?(normalized)
        return false if FALSY_VALUES.include?(normalized)

        default
      end

      def gtm_enabled?(env = ENV)
        enabled?("GTM_ENABLED", default: !staging?(env), env: env)
      end
    end
  end
end
