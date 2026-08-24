# frozen_string_literal: true

module Stores
  module AiAutofill
    class Settings
      DEFAULT_MODEL = "gpt-5.6-terra"

      class ConfigurationError < StandardError; end

      attr_reader :api_key, :model

      def self.from_env(env = ENV)
        api_key = env["OPENAI_API_KEY"].to_s.strip
        raise ConfigurationError, "OPENAI_API_KEY is not configured" if api_key.blank?

        model = env["OPENAI_STORE_AUTOFILL_MODEL"].to_s.strip.presence || DEFAULT_MODEL
        new(api_key:, model:)
      end

      def initialize(api_key:, model:)
        @api_key = api_key
        @model = model
      end
    end
  end
end
