# frozen_string_literal: true

require "digest"
require "json"

module LpAnalytics
  module Sheets
    class Settings
      class ConfigurationError < StandardError; end

      ENV_KEYS = {
        enabled: "LP_ANALYTICS_SHEETS_EXPORT_ENABLED",
        region: "AWS_REGION",
        spreadsheet_id: "GOOGLE_SHEETS_SPREADSHEET_ID",
        worksheet_name: "GOOGLE_SHEETS_WORKSHEET_NAME",
        credentials_secret_id: "GOOGLE_SHEETS_CREDENTIALS_SECRET_ID"
      }.freeze

      attr_reader :region, :spreadsheet_id, :worksheet_name, :credentials_secret_id

      def self.from_env(env: ENV, rails_environment: Rails.env)
        new(
          enabled: env[ENV_KEYS.fetch(:enabled)],
          region: env[ENV_KEYS.fetch(:region)],
          spreadsheet_id: env[ENV_KEYS.fetch(:spreadsheet_id)],
          worksheet_name: env[ENV_KEYS.fetch(:worksheet_name)],
          credentials_secret_id: env[ENV_KEYS.fetch(:credentials_secret_id)],
          rails_environment: rails_environment
        )
      end

      def initialize(
        enabled:,
        region:,
        spreadsheet_id:,
        worksheet_name:,
        credentials_secret_id:,
        rails_environment:
      )
        @enabled = ActiveModel::Type::Boolean.new.cast(enabled)
        @region = region.to_s.strip
        @spreadsheet_id = spreadsheet_id.to_s.strip
        @worksheet_name = worksheet_name.to_s.strip
        @credentials_secret_id = credentials_secret_id.to_s.strip
        @rails_environment = rails_environment.to_s
      end

      def automatic_export_enabled?
        rails_environment == "production" && enabled
      end

      def validate!
        missing = {
          region: region,
          spreadsheet_id: spreadsheet_id,
          worksheet_name: worksheet_name,
          credentials_secret_id: credentials_secret_id
        }.filter_map { |key, value| ENV_KEYS.fetch(key) if value.blank? }
        raise ConfigurationError, "missing required settings: #{missing.join(', ')}" if missing.any?
        raise ConfigurationError, "worksheet name is too long" if worksheet_name.length > 100

        self
      end

      def destination_fingerprint
        validate!
        Digest::SHA256.hexdigest(JSON.generate([ spreadsheet_id, worksheet_name ]))
      end

      private

      attr_reader :enabled, :rails_environment
    end
  end
end
